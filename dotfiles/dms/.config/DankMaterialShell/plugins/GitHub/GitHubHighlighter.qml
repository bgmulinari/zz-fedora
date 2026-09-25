import QtQuick
import qs.Common
import org.kde.syntaxhighlighting

// Colors a code block's text by its language, as github.com does, through
// KDE's syntax definitions and their GitHub themes, dark or light as the
// shell is. GitHubMarkdown makes one per code block; without the module
// this file does not load, and code stays one color.
SyntaxHighlighter {
    theme: {
        const named = Repository.theme(Theme.isLightMode ? "GitHub Light" : "GitHub Dark");
        return named.name !== "" ? named : Repository.defaultTheme(Theme.isLightMode ? Repository.LightTheme : Repository.DarkTheme);
    }

    // Takes the definition a fence's language names (GitHubMarkdown.js
    // codeLookup): by its name, else by the file it names. False when
    // neither is known (the library answers "None" then).
    function use(lookup) {
        const known = found => found.name !== "" && found.name !== "None";
        let found = Repository.definitionForName(lookup.name);
        if (!known(found))
            found = Repository.definitionForFileName(lookup.file);
        if (!known(found))
            return false;
        definition = found;
        return true;
    }
}
