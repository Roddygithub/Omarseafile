// Pure functions shared with the portable tests. No network translation at runtime.
function language(choice, locale, registry) {
    choice = String(choice || "").trim()
    if (Object.prototype.hasOwnProperty.call(registry, choice)) return choice
    var code = String(locale || "en").split(/[.@]/)[0].replace(/_/g, "-")
    if (code === "C" || code === "POSIX") return "en"
    if (code === "nb" || code.indexOf("nb-") === 0 || code === "nn" || code.indexOf("nn-") === 0) return "no"
    if (code === "tl" || code.indexOf("tl-") === 0) return "fil"
    if (code === "es" || code.indexOf("es-") === 0) return "es-MX"
    if (/^zh-(TW|HK|MO|Hant)(-|$)/i.test(code)) return "zh-TW"
    if (/^zh(-|$)/i.test(code)) return "zh-CN"
    if (Object.prototype.hasOwnProperty.call(registry, code)) return code
    code = code.split("-")[0]
    return Object.prototype.hasOwnProperty.call(registry, code) ? code : "en"
}

function translate(strings, source, args) {
    var text = Object.prototype.hasOwnProperty.call(strings, source) && typeof strings[source] === "string"
        && strings[source].length ? strings[source] : source
    // A single pass keeps user-supplied names containing %1 or %2 literal.
    return args ? text.replace(/%(\d+)/g, function(token, index) {
        return Number(index) > 0 && Number(index) <= args.length ? String(args[Number(index) - 1]) : token
    }) : text
}
