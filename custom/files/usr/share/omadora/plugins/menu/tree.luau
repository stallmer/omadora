-- The Omadora menu as plain data, plus pure functions that turn a typed query
-- into launcher results. Nothing here touches Noctalia's globals, so
-- tests/luau/menu_test.luau can run it with a stub fuzzy matcher.

local M = {}

-- A result's `query` rewrites the launcher's input. Noctalia's plugin docs say
-- the query must include the provider prefix, but Noctalia 5.4.1 (the version in
-- Fedora 44) builds "/om " + query itself, so a query that repeats the prefix
-- ends up as "/om /om style". Queries here therefore carry no prefix. Recheck
-- this in the VM whenever Noctalia is upgraded.

M.THEMES = {
  "Ayu", "Catppuccin", "Dracula", "Eldritch", "Gruvbox",
  "Kanagawa", "Noctalia", "Nord", "Rosé Pine", "Tokyo-Night",
}

local function terminal(cmd)
  return { kind = "terminal", cmd = cmd .. '; echo; read -r -p "Done. Press Enter to close. "' }
end

local function argv(...)
  return { kind = "argv", argv = { ... } }
end

-- A stable, ASCII-only token for a theme name ("Rosé Pine" -> "rosepine").
local function slug(name)
  local lowered = string.gsub(string.lower(name), "é", "e")
  local cleaned = string.gsub(lowered, "[^%w]", "")
  return cleaned
end
M.slug = slug

local function themeNodes()
  local nodes = {}
  for _, name in ipairs(M.THEMES) do
    table.insert(nodes, {
      key = slug(name),
      title = name,
      glyph = "palette",
      action = argv("omadora-theme-set", name),
    })
  end
  return nodes
end

M.root = {
  key = "",
  children = {
    { key = "apps", title = "Apps", subtitle = "Search installed applications", glyph = "apps",
      action = { kind = "apps" } },
    { key = "style", title = "Style", subtitle = "Theme, mode and wallpaper", glyph = "palette",
      children = {
        { key = "theme", title = "Theme", subtitle = "Switch the color theme", glyph = "palette",
          children = themeNodes() },
        { key = "mode", title = "Mode", subtitle = "Dark, light or automatic", glyph = "sun-moon",
          children = {
            { key = "dark", title = "Dark", glyph = "moon", action = argv("omadora-theme-set", "--mode", "dark") },
            { key = "light", title = "Light", glyph = "sun", action = argv("omadora-theme-set", "--mode", "light") },
            { key = "auto", title = "Automatic", subtitle = "Follow sunrise and sunset", glyph = "sun-moon",
              action = argv("omadora-theme-set", "--mode", "auto") },
          } },
        { key = "wallpaper", title = "Wallpaper", subtitle = "Pick a wallpaper", glyph = "photo",
          action = argv("noctalia", "msg", "panel-toggle", "wallpaper") },
      } },
    { key = "setup", title = "Setup", subtitle = "Audio, network, printers and keybindings", glyph = "settings",
      children = {
        { key = "audio", title = "Audio", glyph = "volume",
          action = argv("noctalia", "msg", "panel-toggle", "control-center", "audio") },
        { key = "control", title = "Network and Bluetooth", subtitle = "Open the control center", glyph = "wifi",
          action = argv("noctalia", "msg", "panel-toggle", "control-center") },
        { key = "printers", title = "Printers", subtitle = "Set up a printer", glyph = "printer",
          action = argv("system-config-printer") },
        { key = "keybindings", title = "Keybindings", subtitle = "Show the keyboard shortcuts", glyph = "keyboard",
          action = argv("niri", "msg", "action", "show-hotkey-overlay") },
      } },
    { key = "install", title = "Install", subtitle = "Command-line and development tools", glyph = "download",
      children = {
        { key = "tools", title = "Default tools", subtitle = "Homebrew: your everyday command-line tools", glyph = "terminal-2",
          action = terminal("ujust install-default-apps") },
        { key = "dev", title = "Development tools", subtitle = "Homebrew: bats, gh, shellcheck and more", glyph = "code",
          action = terminal("ujust install-dev-tools") },
      } },
    { key = "update", title = "Update", subtitle = "Update the system, Flatpaks, Homebrew and dotfiles", glyph = "refresh",
      action = terminal("omadora-update") },
    { key = "system", title = "System", subtitle = "Lock, suspend and power", glyph = "power",
      children = {
        { key = "lock", title = "Lock", glyph = "lock", action = argv("noctalia", "msg", "session", "lock") },
        { key = "suspend", title = "Suspend", glyph = "player-pause", action = argv("noctalia", "msg", "session", "suspend") },
        { key = "power", title = "Power menu", subtitle = "Log out, restart or shut down", glyph = "power",
          action = argv("noctalia", "msg", "panel-toggle", "session") },
      } },
  },
}

-- Give every node its full id ("style/theme/gruvbox") and a link to its parent.
local function annotate(node, parent, path)
  node.parent = parent
  node.path = path
  if node.children then
    for _, child in ipairs(node.children) do
      local childPath = path == "" and child.key or (path .. "/" .. child.key)
      child.id = childPath
      annotate(child, node, childPath)
    end
  end
end
annotate(M.root, nil, "")

local function find(node, id)
  if node.id == id then
    return node
  end
  if node.children then
    for _, child in ipairs(node.children) do
      local found = find(child, id)
      if found then
        return found
      end
    end
  end
  return nil
end

-- The query (behind the prefix) that shows a node's children. The top level is a
-- single space: an empty string might be read as "no query".
local function queryFor(node)
  if node.path == "" then
    return " "
  end
  local words = string.gsub(node.path, "/", " ")
  return words .. " "
end

-- Split the typed text (everything after the prefix) into the menu level it
-- names and the leftover words, which filter that level.
function M.resolve(text)
  local node = M.root
  local rest = {}
  local walking = true
  for token in string.gmatch(string.lower(text or ""), "%S+") do
    local nextNode = nil
    if walking and node.children then
      for _, child in ipairs(node.children) do
        if child.key == token and child.children then
          nextNode = child
          break
        end
      end
    end
    if nextNode then
      node = nextNode
    else
      walking = false
      table.insert(rest, token)
    end
  end
  return node, table.concat(rest, " ")
end

-- Results for the typed text. `fuzzy(pattern, text)` returns a score or nil.
function M.results(text, fuzzy)
  local node, filter = M.resolve(text)
  local results = {}
  if node.parent then
    table.insert(results, {
      id = "back:" .. node.path,
      title = "Back",
      glyph = "arrow-left",
      query = queryFor(node.parent),
      score = 1000,
    })
  end
  for index, child in ipairs(node.children or {}) do
    local score = 100 - index
    if filter ~= "" then
      score = fuzzy(filter, child.title)
    end
    if score ~= nil then
      local result = {
        id = child.id,
        title = child.title,
        subtitle = child.subtitle,
        glyph = child.glyph,
        score = score,
      }
      if child.children then
        result.query = queryFor(child)
      end
      table.insert(results, result)
    end
  end
  return results
end

-- The action for a leaf id, or nil.
function M.action(id)
  local node = find(M.root, id)
  if node == nil then
    return nil
  end
  return node.action
end

return M
