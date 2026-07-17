class RscListBox;
class CL_Planning_ListBox_Multi : RscListBox {
    style = 16;
};

class CfgPatches {
    class A3A_Ultimate_Tweaks_Extender {
        name = "Antistasi Ultimate Tweaks Extender";
        units[] = {};
        weapons[] = {};
        requiredVersion = 1.0;
        requiredAddons[] = {"A3A_core"};
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

        // =====================================================
        // CL ANTISTASI TWEAKS - BUILDER
        // =====================================================
        class CL_Tweaks_Builder_Spacer : ExtenderParams {
            title = "--- CL Tweaks: Builder ---";
            tooltip = "Construction box and builder UI settings.";
            values[] = {0};
            texts[] = {""};
            default = 0;
        };
        class A3A_tweak_autoBuild : ExtenderParams {
            title = "Instant Construction";
            tooltip = "Instantly builds objects placed from construction crates without needing manual engineer tool assembly.";
            values[] = {0, 1};
            texts[] = {"Disabled (Manual)", "Enabled (Instant)"};
            default = 1;
        };
        /*
        class A3A_tweak_builderDistance : ExtenderParams {
            title = "Interaction Distance";
            tooltip = "Max distance (in meters) from which engineers can build or cancel unbuilt blueprint boxes. Applies to newly placed boxes.";
            values[] = {8, 10, 12, 16, 20, 25, 30};
            texts[] = {"8m (Default)", "10m", "12m", "16m", "20m", "25m", "30m"};
            default = 8;
        };
        */
        class A3A_tweak_builderChainRadius : ExtenderParams {
            title = "Chain Build Radius";
            tooltip = "When you manually finish building one object, other unbuilt objects within this radius are also completed automatically. 0 = Disabled. Only applies with manual construction.";
            values[] = {0, 5, 10, 15, 20, 30, 50};
            texts[] = {"Disabled (0m)", "5 Meters", "10 Meters", "15 Meters", "20 Meters", "30 Meters", "50 Meters"};
            default = 0;
        };
        // =====================================================
        // CL ANTISTASI TWEAKS - SELF-REVIVE
        // =====================================================
        class CL_Tweaks_SelfRevive_Spacer : ExtenderParams {
            title = "--- CL Tweaks: Self-Revive ---";
            tooltip = "Settings for the self-revive mechanic.";
            values[] = {0};
            texts[] = {""};
            default = 0;
        };
        class A3A_selfReviveTweak_NoKit : ExtenderParams {
            title = "FAK Requirement";
            tooltip = "Requires a First Aid Kit (or rebel healing item) to perform self-revive, or disables the check entirely.";
            values[] = {0, 1};
            texts[] = {"Requires First Aid Kit", "No Kit Required"};
            default = 0;
        };
        class A3A_selfReviveTweak_Cooldown : ExtenderParams {
            title = "Cooldown (Seconds)";
            tooltip = "Cooldown in seconds between consecutive self-revives.";
            values[] = {0, 30, 60, 120, 300, 600};
            texts[] = {"0s (No Cooldown)", "30s", "60s (1 min)", "120s (2 min)", "300s (5 min)", "600s (10 min)"};
            default = 300;
        };
        class A3A_selfReviveTweak_Damage : ExtenderParams {
            title = "Damage After Revive";
            tooltip = "The amount of damage the player has immediately after self-reviving.";
            values[] = {0, 25, 50, 75};
            texts[] = {"0% (Full Health)", "25% Wounded", "50% Wounded (Default)", "75% Wounded"};
            default = 50;
        };

        // =====================================================
        // CL ANTISTASI TWEAKS - PETROS / MISSIONS
        // =====================================================
        class CL_Tweaks_Petros_Spacer : ExtenderParams {
            title = "--- CL Tweaks: Petros & Missions ---";
            tooltip = "Settings for Petros mission requests and random events.";
            values[] = {0};
            texts[] = {""};
            default = 0;
        };
        class A3A_tweak_missionCooldown : ExtenderParams {
            title = "Request Cooldown";
            tooltip = "Cooldown in minutes before you can request a manual mission from Petros again.";
            values[] = {0, 3, 5, 10, 15, 30};
            texts[] = {"No Cooldown", "3 Minutes", "5 Minutes", "10 Minutes", "15 Minutes", "30 Minutes"};
            default = 0;
        };
        class A3A_tweak_randomMissionChanceMultiplier : ExtenderParams {
            title = "Random Mission Chance";
            tooltip = "Multiplier for Petros triggering random missions periodically. Higher = more frequent random events.";
            values[] = {0, 0.5, 1, 2, 5};
            texts[] = {"Disabled (0x)", "Half (0.5x)", "Normal (1x)", "Double (2x)", "High (5x)"};
            default = 1;
        };

        // =====================================================
        // CL ANTISTASI TWEAKS - FAST TRAVEL
        // =====================================================
        class CL_Tweaks_FastTravel_Spacer : ExtenderParams {
            title = "--- CL Tweaks: Fast Travel ---";
            tooltip = "Settings for the fast travel system.";
            values[] = {0};
            texts[] = {""};
            default = 0;
        };
        class A3A_tweak_fastTravelSpeedMultiplier : ExtenderParams {
            title = "Speed Multiplier";
            tooltip = "Multiplier applied to fast travel time. 'Instant' skips the black-screen wait entirely.";
            values[] = {1, 2, 5, 10, 9999};
            texts[] = {"1x (Default)", "2x Faster", "5x Faster", "10x Faster", "Instant (No Wait)"};
            default = 1;
        };

        // =====================================================
        // CL ANTISTASI TWEAKS - HQ & BASES
        // =====================================================
        class CL_Tweaks_HQ_Spacer : ExtenderParams {
            title = "--- CL Tweaks: HQ & Bases ---";
            tooltip = "Settings for vehicle/static saving around HQ and friendly bases.";
            values[] = {0};
            texts[] = {""};
            default = 0;
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
            texts[] = {"0m (Strict Boundary)", "25m", "50m", "75m", "100m", "150m", "200m"};
            default = 0;
        };

        // =====================================================
        // CL ANTISTASI TWEAKS - FOG OF WAR
        // =====================================================
        class CL_Tweaks_FogOfWar_Spacer : ExtenderParams {
            title = "--- CL Tweaks: Fog of War ---";
            tooltip = "Settings for discovering and auto-revealing hidden enemy outposts.";
            values[] = {0};
            texts[] = {""};
            default = 0;
        };
        class A3A_tweak_discoveryReveal : ExtenderParams {
            title = "Auto-Reveal";
            tooltip = "Automatically reveals hidden enemy outposts on the map when you get close.";
            values[] = {0, 1};
            texts[] = {"Disabled", "Enabled"};
            default = 1;
        };
        class A3A_tweak_discoveryDistance : ExtenderParams {
            title = "Reveal Distance";
            tooltip = "Max distance (in meters) from the outpost center/flag to trigger discovery.";
            values[] = {50, 100, 150, 200, 300, 500};
            texts[] = {"50m", "100m", "150m", "200m (Default)", "300m", "500m"};
            default = 200;
        };

        // =====================================================
        // CL ANTISTASI TWEAKS - SIEGE PLANNING
        // =====================================================
        class CL_Tweaks_Siege_Spacer : ExtenderParams {
            title = "--- CL Tweaks: Siege Planning ---";
            tooltip = "Settings for siege and attack planning.";
            values[] = {0};
            texts[] = {""};
            default = 0;
        };
        class A3A_tweak_maxSiegeSquads : ExtenderParams {
            title = "Max Siege Squads";
            tooltip = "The maximum number of squads that can participate in a siege (1 to 20).";
            values[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20};
            texts[] = {"1 Squad", "2 Squads", "3 Squads", "4 Squads", "5 Squads", "6 Squads", "7 Squads", "8 Squads", "9 Squads", "10 Squads (Default)", "11 Squads", "12 Squads", "13 Squads", "14 Squads", "15 Squads", "16 Squads", "17 Squads", "18 Squads", "19 Squads", "20 Squads"};
            default = 10;
        };
        class A3A_tweak_siegeRefundOrGarrison : ExtenderParams {
            title = "Capture Reward Action";
            tooltip = "Choose whether surviving siege troops are immediately garrisoned at the captured outpost or refunded to the faction database (Money & HR) the instant the objective is captured.";
            values[] = {1, 2};
            texts[] = {"Garrison Surviving Troops", "Refund Surviving Troops (Money & HR)"};
            default = 1;
        };
        class A3A_tweak_siegeTravelTimeMultiplier : ExtenderParams {
            title = "Siege Travel Time";
            tooltip = "Multiplier applied to the travel time for siege squads to reach their staging points.";
            values[] = {0, 0.1, 0.25, 0.5, 1, 2};
            texts[] = {"Instant", "10x Faster", "4x Faster", "2x Faster", "Default", "2x Slower"};
            default = 1;
        };
    };
};

