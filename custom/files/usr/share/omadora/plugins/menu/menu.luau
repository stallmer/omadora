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
    -- Activating without launcher.setQuery closes the launcher. Reopen a plain one
    -- a moment later, so it is not a toggle that closes it again. This does not
    -- depend on how a version of Noctalia builds the launcher's input.
    noctalia.runAsync({ "sh", "-c", "sleep 0.3; exec noctalia msg panel-toggle launcher" })
  end
end
