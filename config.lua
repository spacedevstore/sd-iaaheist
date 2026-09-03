Config = {}

Config.Framework       = 'auto'
Config.Inventory       = 'auto'
Config.GetCoreObject   = 'qb-core'
Config.GetSharedObject = 'es_extended'

Config.RequiredPolice      = 0
Config.Cooldown            = 45
Config.TimeToReset         = 60
Config.MinPlayers          = 1
Config.MaxPlayers          = 4
Config.EnableGuardsPeds    = true
Config.EnablePoliceReport  = true
Config.UsbPrice            = 1000
Config.MaxInteractDistance = 3.5

Config.Enter         = vector3(2477.82, -365.89, 94.02)
Config.Exit          = vector3(2155.05, 2921.00, -62.09)
Config.Finish        = vector3(1735.22, -1630.45, 111.45)
Config.FinishHeading = 247.0

Config.Minigame = {
    blocks = 5,
    time   = 10
}

Config.Items = {
    ['hack_laptop'] = 'laptop',
    ['hack_usb']    = 'trojan_usb',
    ['data_usb']    = 'usb_data'
}


Config.SecurityPanel = {
    {
        object  = 'hei_prop_hei_securitypanel',
        coords  = vector3(2478.02, -367.49, 94.91),
        heading = 135.66,
        used    = false,
        busy    = false
    },
    {
        object  = 'hei_prop_hei_securitypanel',
        coords  = vector3(2047.51, 2964.5, -67.2),
        heading = 142.66,
        used    = false,
        busy    = false
    }
}

Config.LaptopHack = {
    { coords = vector3(2057.55, 2963.21, -67.5), heading = 55.55,  used = false },
    { coords = vector3(2051.83, 2986.2,  -67.5), heading = 145.55, used = false },
    { coords = vector3(2048.33, 2980.07, -67.5), heading = 145.55, used = false },
    { coords = vector3(2060.97, 2969.49, -67.5), heading = 235.55, used = false },
    { coords = vector3(2068.47, 2994.95, -63.7), heading = 142.55, used = false }
}

Config.HackComputers = {
    { coords = vector3(2060.73, 2996.42, -67.7), heading = 43.0,   used = false },
    { coords = vector3(2067.57, 2999.17, -67.7), heading = 352.33, used = false },
    { coords = vector3(2073.46, 2995.05, -67.7), heading = 302.33, used = false },
    { coords = vector3(2073.1,  2987.46, -67.7), heading = 249.33, used = false }
}

Config.ClosedDoors = {
    { object = -147325430, coords = vector3(2050.68, 2963.61, -67.15) },
    { object = -147325430, coords = vector3(2050.68, 2974.79, -67.15) },
    { object = -147325430, coords = vector3(2054.7,  2980.52, -67.15) },
    { object = -147325430, coords = vector3(2054.69, 2969.34, -67.15) }
}

Config.StartPeds = {
    {
        coords  = vector3(1533.84, 1702.51, 108.73),
        model   = 'g_m_m_armboss_01',
        heading = 80.1
    },
    {
        coords  = vector3(1534.67, 1701.94, 108.71),
        model   = 'g_m_y_korean_01',
        heading = 45.96
    },
    {
        coords  = vector3(1534.86, 1703.23, 108.71),
        model   = 'g_m_y_korean_01',
        heading = 82.55
    }
}

Config.GuardSettings = {
    Health                  = 200,
    Armor                   = 100,
    Accuracy                = 65,
    CombatAbility           = 2,
    CombatMovement          = 2,
    CombatRange             = 2,
    VisionDistance          = 45.0,
    VisionAngle             = 75.0,
    HearingDistance         = 60.0,
    FootstepHearingDistance = 9.0,
    EnableFlashlights       = true,
    EnableVoiceChatter      = true,
    EnableBlips             = true,
    BlipDistance            = 100.0,
    DropsWeapons            = false,
    HeadshotsKill           = true,
    DetectionGraceTime      = 2000,
    ShowHelpOnAlert         = true,
    AlertRadius             = 65.0,
    MaxFloorZDiff           = 3.0,
    WanderRadius            = 10.0
}

Config.Guards = {
    {
        coords = vector4(2120.63, 2926.86, -61.9, 124.87),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_COMBATPISTOL'
    },
    {
        coords = vector4(2109.34, 2929.59, -61.9, 212.06),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_SMG'
    },
    {
        coords = vector4(2078.37, 2930.14, -61.9, 278.7),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2033.8,  2942.42, -61.9, 249.12),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_PUMPSHOTGUN'
    },
    {
        coords = vector4(2048.81, 2977.58, -61.9, 19.74),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_SPECIALCARBINE'
    },
    {
        coords = vector4(2053.35, 2982.78, -61.9, 115.93),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2059.78, 2981.66, -67.3, 50.79),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2067.23, 2994.66, -67.7, 96.03),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2069.82, 2991.4, -67.7, 87.42),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2053.12, 2972.62, -67.3, 164.24),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2053.12, 2972.63, -67.3, 164.24),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2104.57, 2942.23, -65.5, 80.36),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2086.68, 2943.54, -65.5, 86.72),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2056.0, 2947.71, -65.5, 37.19),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    },
    {
        coords = vector4(2032.89, 2960.6, -65.5, 166.66),
        model  = 'S_M_M_CIASec_01',
        weapon = 'WEAPON_CARBINERIFLE'
    }
}
