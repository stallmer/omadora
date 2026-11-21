-- Launcher provider entry for the Omadora menu. The menu itself is in tree.luau.

local tree = require("./tree.luau")

local function fuzzy(pattern, text)
  return noctalia.fuzzyScore(pattern, text)
end

function onQuery(text)
  launcher.setResults(text, tree.results(text, fuzzy))
end

function onActivate(id)
  local action = tree.action(id)
  if action == nil then
    return
  end
  if action.kind == "argv" then
    noctalia.runAsync(action.argv)
  elseif action.kind == "terminal" then
    noctalia.runInTerminal(action.cmd)
  elseif action.kind == "apps" then
    -- Clear the input so the launcher goes back to searching applications.
    launcher.setQuery("")
  end
end
