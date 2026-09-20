'use strict';
/*
 * Minimal QML-singleton JavaScript harness.
 *
 * Lets the portable test suites execute the REAL JavaScript that ships inside
 * our singleton .qml modules, instead of re-implementing it in the test (which
 * would verify the stand-in rather than the product).
 *
 * Note: this file deliberately never spells out the QML singleton pragma
 * marker as a literal string. validate.sh flags any .js file containing it, and
 * this harness is a test tool, not a shipped module.
 *
 * It understands exactly the QML subset those modules use inside the root
 * object:
 *   property <type> <name>: <expr>   -> mutable field
 *   readonly property ...            -> mutable field (tests may seed it)
 *   signal <name>(<args>)            -> recording stub
 *   function <name>(...) {...}       -> real function, extracted verbatim
 *
 * Component {} / nested object declarations are ignored. Callers pass `env`
 * for identifiers the module expects in scope (other singletons, Qt, ...).
 */
const fs = require('fs');
const vm = require('vm');

// Remove comments while preserving line/character offsets, so a brace or quote
// inside a comment cannot confuse the scanner. Regex literals are tracked
// because `/^file:\/\//` contains what otherwise looks like a `//` comment.
function blankComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  let str = null;
  let inRegex = false;
  let inClass = false;
  let lastMeaningful = '';

  // After these, a `/` begins a regex literal; otherwise it is division.
  const regexAllowedAfter = /[\w$\]]$/;

  while (i < n) {
    const c = src[i];

    if (inRegex) {
      out += c;
      if (c === '\\') { out += src[i + 1] || ''; i += 2; continue; }
      if (c === '[') inClass = true;
      else if (c === ']') inClass = false;
      else if (c === '/' && !inClass) { inRegex = false; lastMeaningful = '/'; }
      else if (c === '\n') { inRegex = false; inClass = false; }
      i++;
      continue;
    }

    if (str) {
      out += c;
      if (c === '\\') { out += src[i + 1] || ''; i += 2; continue; }
      if (c === str) { str = null; lastMeaningful = c; }
      i++;
      continue;
    }

    if (c === '"' || c === "'" || c === '`') { str = c; out += c; i++; continue; }

    if (c === '/' && src[i + 1] === '/') {
      while (i < n && src[i] !== '\n') { out += ' '; i++; }
      continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) { out += src[i] === '\n' ? '\n' : ' '; i++; }
      out += '  '; i += 2;
      continue;
    }
    if (c === '/' && !regexAllowedAfter.test(lastMeaningful)) {
      inRegex = true;
      out += c;
      i++;
      continue;
    }

    if (!/\s/.test(c)) lastMeaningful = c;
    out += c;
    i++;
  }
  return out;
}

// Find the offset just past the `{` that opens the root object body.
function rootBodyStart(src) {
  let depth = 0;
  let str = null;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (str) {
      if (c === '\\') { i++; continue; }
      if (c === str) str = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { str = c; continue; }
    if (c === '{') return i + 1;
  }
  return -1;
}

// Split a body into brace-balanced top-level member chunks. Assumes comments
// have already been blanked by blankComments().
function topLevelMembers(body) {
  const regexAllowedAfter = /[\w$\]]$/;
  const members = [];
  let i = 0;
  const n = body.length;
  while (i < n) {
    while (i < n && /\s/.test(body[i])) i++;
    if (i >= n) break;
    const start = i;
    let depth = 0;
    let paren = 0;
    let bracket = 0;
    let str = null;
    let inRegex = false;
    let inClass = false;
    let lastMeaningful = '';
    let sawOpen = false;
    let done = false;
    for (; i < n; i++) {
      const c = body[i];
      if (inRegex) {
        if (c === '\\') { i++; continue; }
        if (c === '[') inClass = true;
        else if (c === ']') inClass = false;
        else if (c === '/' && !inClass) { inRegex = false; lastMeaningful = '/'; }
        else if (c === '\n') { inRegex = false; inClass = false; }
        continue;
      }
      if (str) {
        if (c === '\\') { i++; continue; }
        if (c === str) { str = null; lastMeaningful = c; }
        continue;
      }
      if (c === '"' || c === "'" || c === '`') { str = c; continue; }
      if (c === '/' && !regexAllowedAfter.test(lastMeaningful)) { inRegex = true; continue; }
      if (c === '(') { paren++; lastMeaningful = c; continue; }
      if (c === ')') { paren--; lastMeaningful = c; continue; }
      if (c === '[') { bracket++; lastMeaningful = c; continue; }
      if (c === ']') { bracket--; lastMeaningful = c; continue; }
      if (c === '{') {
        // A brace inside parentheses is an object literal (e.g. `({})`), not
        // the start of a QML object block.
        if (paren === 0) { depth++; sawOpen = true; }
        lastMeaningful = c;
        continue;
      }
      if (c === '}') {
        if (paren === 0) { depth--; if (sawOpen && depth === 0) { i++; done = true; break; } }
        lastMeaningful = c;
        continue;
      }
      // A newline ends the member only when no grouping is still open, so a
      // multi-line initializer like `({})` or `[\n 1,\n 2\n]` stays intact.
      if (!sawOpen && c === '\n' && paren === 0 && bracket === 0 && !inRegex) { i++; done = true; break; }
      if (!/\s/.test(c)) lastMeaningful = c;
    }
    const text = body.slice(start, i);
    if (text.trim() !== '') members.push(text);
    if (!done && i >= n) break;
  }
  return members;
}

// True when `expr` opens a QML object block, i.e. a `{` that is not nested
// inside parentheses. `({})` and `({ a: 1 })` are object literals; `Process {`
// and `Component {` are object declarations.
function hasTopLevelBrace(expr) {
  let paren = 0;
  let str = null;
  for (let i = 0; i < expr.length; i++) {
    const c = expr[i];
    if (str) {
      if (c === '\\') { i++; continue; }
      if (c === str) str = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { str = c; continue; }
    if (c === '(') { paren++; continue; }
    if (c === ')') { paren--; continue; }
    if (c === '{' && paren === 0) return true;
  }
  return false;
}

function loadQmlObject(path, env) {
  const raw = fs.readFileSync(path, 'utf8');
  const src = blankComments(
    raw.split('\n').filter(l => !/^\s*pragma\s+Singleton/.test(l) && !/^\s*import\s/.test(l)).join('\n')
  );
  const start = rootBodyStart(src);
  if (start < 0) throw new Error('no root object found in ' + path);
  const members = topLevelMembers(src.slice(start));

  // Web/JS globals the QML engine provides and our singletons rely on.
  const ctx = Object.assign({ console: console, Math: Math, JSON: JSON, Date: Date,
                              Array: Array, Object: Object, String: String, Number: Number,
                              Boolean: Boolean, RegExp: RegExp, Error: Error,
                              parseInt: parseInt, parseFloat: parseFloat, isNaN: isNaN,
                              isFinite: isFinite, encodeURIComponent: encodeURIComponent,
                              decodeURIComponent: decodeURIComponent, URL: URL }, env || {});
  vm.createContext(ctx);
  // QML root objects carry an `id` (conventionally `root`) that every member
  // function closes over. Mirror the context onto itself so `root.foo` resolves
  // to the same fields the test harness reads and writes.
  ctx.root = ctx;
  const idMatch = /^\s*id:\s*(\w+)/m.exec(src.slice(start, start + 400));
  if (idMatch && idMatch[1] !== 'root') ctx[idMatch[1]] = ctx;

  const pendingProps = [];
  const fnSources = [];

  for (const m of members) {
    const trimmed = m.trim();
    const prop = trimmed.match(/^(?:readonly\s+)?property\s+(?:[\w.<>]+)\s+(\w+)\s*:([\s\S]*)$/);
    if (prop) {
      // A property whose initializer opens a real block (Component { ... },
      // Timer { ... }) is an object declaration, not a value. `({})` is a plain
      // object literal because the brace sits inside parentheses.
      if (hasTopLevelBrace(prop[2])) continue;
      pendingProps.push([prop[1], prop[2].trim()]);
      continue;
    }
    const sig = trimmed.match(/^signal\s+(\w+)\s*\(([^)]*)\)/);
    if (sig) {
      const name = sig[1];
      ctx['_' + name + 'Calls'] = [];
      vm.runInContext('this.' + name + ' = function(){ this._' + name + 'Calls.push(Array.prototype.slice.call(arguments)); }', ctx);
      continue;
    }
    if (/^function\s+\w+\s*\(/.test(trimmed)) fnSources.push(trimmed);
  }

  // Properties first (two passes so later ones may reference earlier ones).
  for (const [name, expr] of pendingProps) {
    try { ctx[name] = vm.runInContext('(' + (expr === '' ? 'undefined' : expr) + ')', ctx); }
    catch (e) { ctx[name] = undefined; }
  }
  // Function declarations: install as named declarations so they hoist and can
  // call each other, then expose them on the context object.
  if (fnSources.length) {
    vm.runInContext(fnSources.join('\n\n') + '\n\n;' +
      fnSources.map(f => 'this.' + f.match(/^function\s+(\w+)/)[1] + ' = ' + f.match(/^function\s+(\w+)/)[1] + ';').join('\n'), ctx);
  }
  return ctx;
}

// Extract the verbatim source of one QML function for embedding in a harness.
function extractFunction(path, name) {
  const src = blankComments(fs.readFileSync(path, 'utf8'));
  const re = new RegExp('function\\s+' + name + '\\s*\\(');
  const m = re.exec(src);
  if (!m) throw new Error('function ' + name + ' not found in ' + path);
  let i = src.indexOf('{', m.index);
  const start = m.index;
  let depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) { i++; break; } }
  }
  return src.slice(start, i);
}

module.exports = { loadQmlObject, extractFunction, topLevelMembers, blankComments };
