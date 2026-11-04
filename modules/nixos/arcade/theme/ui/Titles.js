.pragma library

// Until a system is scraped, Pegasus knows each game only by its file name, in
// No-Intro's form: "Addams Family, The (USA, Europe) (Rev A)". These turn that
// into a title to show and the tags to show beside it. A scraped title has no
// tags, so it passes through untouched.

var languages = /^(En|Fr|De|Es|It|Nl|Pt|Sv|No|Da|Fi|Ja|Zh|Ko|Ru|Pl)$/;
var trailing = /\s*[\(\[]([^\)\]]*)[\)\]]\s*$/;
// "Addams Family, The" and "Simpsons, The - Bart's Nightmare"
var article = /^(.+?), (The|A|An)((?:\s+[-~]\s+.*)?)$/;

function parse(raw) {
    var title = String(raw || "");
    var groups = [];
    var match;
    while ((match = trailing.exec(title)) !== null && match.index > 0) {
        groups.unshift(match[1]);
        title = title.slice(0, match.index);
    }

    var tags = [];
    groups.forEach(function (group) {
        var parts = group.split(/\s*,\s*/);
        // A language list says nothing a player chooses by.
        if (parts.every(function (part) { return languages.test(part); }))
            return;
        parts.forEach(function (part) {
            if (part && tags.indexOf(part) < 0)
                tags.push(part);
        });
    });

    var moved = article.exec(title);
    if (moved)
        title = moved[2] + " " + moved[1] + moved[3];

    return { title: title.trim(), tags: tags };
}

var minor = { "the": true, "a": true, "an": true, "of": true, "and": true, "in": true,
              "&": true, "-": true, "~": true, "+": true };

// Two letters for a game with no art: "Sonic the Hedgehog" is SH.
function initials(title) {
    var words = String(title || "").split(/\s+/).filter(function (word) {
        return word && !minor[word.toLowerCase()];
    });
    var letters = words.slice(0, 2).map(function (word) {
        return word.charAt(0).toUpperCase();
    }).join("");
    return letters || "?";
}

// The letter a game files under, as the list is sorted: by its raw title, so
// "Addams Family, The" is under A.
function letter(raw) {
    var first = String(raw || "").charAt(0).toUpperCase();
    return first >= "A" && first <= "Z" ? first : "#";
}
