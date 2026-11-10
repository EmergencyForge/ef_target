Config = {
    Key = 'LMENU',           -- hold to open the targeting view
    UseKey = 'E',            -- activates the highlighted entry, like left click
    Toggle = false,          -- true: press once to open, again to close
    Reticle = {
        Thickness = 2.0,     -- line width of the own marker in pixels at 1080p, 1.0 to 3.5
        CenterDot = false,   -- dot in the middle of the own marker
    },
    MenuScale = 1.0,         -- size of the menu in the world, 1.0 is about 9 cm per key at 2.5 m
    SnapRadius = 0.035,     -- share of screen height within which the cursor snaps to a point
    MaxPoints = 24,          -- points shown at once
    DefaultPoints = true,    -- built-in points for vehicles
    DefaultDistance = 7.0,   -- default reach of an option, in metres
    RayLength = 20.0,        -- how far the scan ray looks
    Locale = 'de',
}
