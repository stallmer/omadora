-- Tests for the Omadora menu logic (custom/files/usr/share/omadora/plugins/menu/tree.luau).
-- Run with: luau tests/luau/menu_test.luau   (from the repository root)

local tree = require("../../custom/files/usr/share/omadora/plugins/menu/tree")

local failures = 0
local function check(cond, message)
  if not cond then
    failures += 1
    print("FAIL: " .. message)
  end
end

-- A simple stand-in for Noctalia's fuzzy matcher: case-insensitive substring.
local function fuzzy(pattern, text)
  if string.find(string.lower(text), string.lower(pattern), 1, true) then
    return 50
  end
  return nil
end

local function titles(results)
  local out = {}
  for _, r in ipairs(results) do
    table.insert(out, r.title)
  end
  return table.concat(out, ",")
end

local function find(results, title)
  for _, r in ipairs(results) do
    if r.title == title then
      return r
    end
  end
  return nil
end

-- Top level.
local top = tree.results("", fuzzy)
check(titles(top) == "Apps,Style,Setup,Install,Update,System", "top level lists the six entries in order, got: " .. titles(top))
check(top[1].query == nil, "Apps is a leaf and has no drill-in query")
check(find(top, "Style").query == "style ", "Style drills into 'style ' (no prefix), got: " .. tostring(find(top, "Style").query))
check(find(top, "Update").query == nil, "Update is a leaf")

-- Drilling in.
local style = tree.results("style", fuzzy)
check(titles(style) == "Back,Theme,Mode,Wallpaper", "style level, got: " .. titles(style))
check(style[1].query == " ", "Back from style returns to the top with a single space, got: " .. tostring(style[1].query))
check(find(style, "Theme").query == "style theme ", "Theme drills into 'style theme '")
check(find(style, "Wallpaper").query == nil, "Wallpaper is an action, not a drill-in")
local wallpaper = tree.action("style/wallpaper")
check(wallpaper ~= nil and wallpaper.argv[3] == "panel-toggle" and wallpaper.argv[4] == "wallpaper", "Wallpaper opens the wallpaper panel")

-- Leading and extra spaces are ignored, and case does not matter.
check(titles(tree.results("  Style  ", fuzzy)) == titles(style), "whitespace and case are ignored")

-- The theme list has all ten themes plus Back, and activating one sets it.
local themes = tree.results("style theme", fuzzy)
check(#themes == 11, "theme level has Back plus ten themes, got " .. #themes)
check(themes[1].query == "style ", "Back from theme returns to style")
local gruvbox = find(themes, "Gruvbox")
check(gruvbox ~= nil and gruvbox.id == "style/theme/gruvbox", "Gruvbox id is its path")
local action = tree.action("style/theme/gruvbox")
check(action ~= nil and action.kind == "argv", "Gruvbox is an argv action")
check(action.argv[1] == "omadora-theme-set" and action.argv[2] == "Gruvbox", "Gruvbox runs omadora-theme-set Gruvbox")
local rose = tree.action("style/theme/rosepine")
check(rose ~= nil and rose.argv[2] == "Rosé Pine", "Rosé Pine keeps its accent in the command")
local tokyo = tree.action("style/theme/tokyonight")
check(tokyo ~= nil and tokyo.argv[2] == "Tokyo-Night", "Tokyo-Night maps to its id")
check(#tree.THEMES == 10, "ten bundled themes")

-- Every theme named in the menu is a theme omadora-theme-set accepts.
for _, name in ipairs(tree.THEMES) do
  check(tree.action("style/theme/" .. tree.slug(name)) ~= nil, "theme action exists for " .. name)
end

-- Modes.
local light = tree.action("style/mode/light")
check(light ~= nil and light.argv[2] == "--mode" and light.argv[3] == "light", "Light runs omadora-theme-set --mode light")

-- Filtering inside a level.
local filtered = tree.results("style theme tok", fuzzy)
check(titles(filtered) == "Back,Tokyo-Night", "typing 'tok' in the theme level keeps Back and Tokyo-Night, got: " .. titles(filtered))
local none = tree.results("style theme zzz", fuzzy)
check(titles(none) == "Back", "a filter with no match leaves only Back, got: " .. titles(none))
local topFiltered = tree.results("upd", fuzzy)
check(titles(topFiltered) == "Update", "typing 'upd' at the top finds Update, got: " .. titles(topFiltered))

-- Leaf actions.
check(tree.action("apps").kind == "apps", "Apps asks the entry to clear the launcher input")
local update = tree.action("update")
check(update.kind == "terminal" and string.find(update.cmd, "omadora-update", 1, true) ~= nil, "Update runs omadora-update in a terminal")
check(string.find(tree.action("install/tools").cmd, "ujust install-default-apps", 1, true) ~= nil, "Install default tools runs the ujust recipe")
check(string.find(tree.action("install/dev").cmd, "ujust install-dev-tools", 1, true) ~= nil, "Install development tools runs the ujust recipe")
local lock = tree.action("system/lock")
check(lock.argv[1] == "noctalia" and lock.argv[4] == "lock", "Lock runs noctalia msg session lock")
check(tree.action("setup/keybindings").argv[4] == "show-hotkey-overlay", "Keybindings shows Niri's hotkey overlay")
check(tree.action("setup/printers").argv[1] == "system-config-printer", "Printers opens the printer setup")

-- No query repeats the provider prefix: Noctalia 5.4.1 prepends it itself.
local function noPrefix(text)
  for _, r in ipairs(tree.results(text, fuzzy)) do
    if r.query ~= nil then
      check(string.sub(r.query, 1, 1) ~= "/", "query '" .. r.query .. "' must not start with a prefix")
    end
  end
end
noPrefix("")
noPrefix("style")
noPrefix("style theme")
noPrefix("setup")

-- Apps reopens a plain launcher instead of setting a prefixed query.
check(tree.action("apps").kind == "apps", "Apps keeps its own action kind")

-- Unknown ids and non-leaf ids have no action.
check(tree.action("nope") == nil, "unknown id has no action")
check(tree.action("style") == nil, "a menu level has no action")

if failures > 0 then
  print(failures .. " check(s) failed")
  error("menu tests failed")
end
print("all menu checks passed")
