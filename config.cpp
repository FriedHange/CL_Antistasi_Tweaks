class CfgPatches {
    class A3A_Ultimate_Tweaks_Extender {
        name = "Antistasi Ultimate Tweaks Extender";
        units[] = {};
        weapons[] = {};
        requiredVersion = 1.0;
        requiredAddons[] = {"A3A_core", "A3A_gui"};
        author = "Antigravity";
    };
};

class CfgFunctions {
    class A3A_Ultimate_Tweaks_Extender {
        class tweaks {
            file = "\CL_Antistasi_Tweaks\functions";
            class postInit { postInit = 1; };
        };
    };
};

class A3A {
    class Params {
        class ExtenderParams; // Forward declaration
        
        class A3A_tweak_autoBuild : ExtenderParams {
            title = "Builder: Instant/Auto Construction";
            tooltip = "Instantly builds objects placed from construction crates without needing manual engineer tool assembly.";
            values[] = {0, 1};
            texts[] = {"Disabled (Manual Construction)", "Enabled (Instant Construction)"};
            default = 0;
        };
        
        class A3A_selfReviveTweak_NoKit : ExtenderParams {
            title = "Self-Revive: FAK Requirement";
            tooltip = "Requires a First Aid Kit (or rebel healing item) to perform self-revive, or disables the check entirely.";
            values[] = {0, 1};
            texts[] = {"Requires First Aid Kit", "No Kit Required"};
            default = 0;
        };
        class A3A_selfReviveTweak_Cooldown : ExtenderParams {
            title = "Self-Revive: Cooldown (Seconds)";
            tooltip = "Cooldown in seconds between consecutive self-revives.";
            values[] = {0, 30, 60, 120, 300, 600};
            texts[] = {"0s (No Cooldown)", "30s", "60s (1 Minute)", "120s (2 Minutes)", "300s (5 Minutes)", "600s (10 Minutes)"};
            default = 300;
        };
        class A3A_selfReviveTweak_Damage : ExtenderParams {
            title = "Self-Revive: Damage Received";
            tooltip = "The amount of damage/wounds the player has immediately after self-reviving.";
            values[] = {0, 25, 50, 75};
            texts[] = {"0% (Full Health)", "25% Wounded", "50% Wounded (Default)", "75% Wounded"};
            default = 50;
        };
        class A3A_tweak_saveRadiusHQ : ExtenderParams {
            title = "HQ: Vehicle/Static Save Radius";
            tooltip = "The distance around the rebel HQ where vehicles and static weapons are saved.";
            values[] = {25, 50, 75, 100, 150, 200};
            texts[] = {"25m", "50m (Default)", "75m", "100m", "150m", "200m"};
            default = 50;
        };
        class A3A_tweak_saveRadiusBuffer : ExtenderParams {
            title = "Bases: Save Radius Buffer";
            tooltip = "Extra distance (in meters) added to the border area of friendly outposts/airbases for saving vehicles and statics.";
            values[] = {0, 25, 50, 75, 100, 150, 200};
            texts[] = {"0m (Strict Marker Boundaries)", "25m", "50m", "75m", "100m", "150m", "200m"};
            default = 0;
        };
    };
};

class A3A_teamLeaderBuilder
{
    class ControlsBackground
    {
        class TitleBarBackground
        {
            y = (safeZoneY + safeZoneH) - 77 * (pixelH * 2 * pixelScale);
        };
        class Background
        {
            y = (safeZoneY + safeZoneH) - 72 * (pixelH * 2 * pixelScale);
            h = 72 * (pixelH * 2 * pixelScale);
        };
    };
    class Controls
    {
        class TitlebarText
        {
            y = (safeZoneY + safeZoneH) - 77 * (pixelH * 2 * pixelScale);
        };
        class RemMoneyText
        {
            y = (safeZoneY + safeZoneH) - 77 * (pixelH * 2 * pixelScale);
        };
        class MainContent
        {
            y = (safeZoneY + safeZoneH) - 72 * (pixelH * 2 * pixelScale);
            h = 72 * (pixelH * 2 * pixelScale);
            class Controls
            {
                class BuildingControlsGroup
                {
                    h = 68 * (pixelH * 2 * pixelScale);
                };
            };
        };
    };
};

