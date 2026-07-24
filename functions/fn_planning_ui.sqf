/*
	    fn_planning_ui.sqf
	    Builds, populates, and manages the redesigned Siege Planning Rework tab dynamically.
	    guided workflow: Target Selection -> Staging Areas (Entry Points) -> Squad Queue & Assignment -> Commencement.
	
	    FIXES APPLIED:
	      1. Squad listbox (8020) and both combo boxes (8022, 8030) now get explicit
	         background/text colors matching the rest of the dark theme (was previously
	         using default engine styling, causing the "visual bug" mismatch with the
	         queue list below).
	      2. Layout below the staging dropdown is now computed dynamically based on
	         whether the vehicle crew selector (8031/8030) is actually visible. Previously
	         the Queue button, queue list, remove button, cost label, and commence button
	         were all pinned at fixed Y offsets that assumed the vehicle selector was
	         always taking up space -- leaving a permanent ~4uH dead gap whenever a
	         non-crew squad type was selected (the default state). The panel now
	         collapses tightly when that selector is hidden.
*/

disableSerialization;
params [["_display", findDisplay 60000, [displayNull]]];

if (isNull _display) exitWith {};

// Ensure vehicle availability cache is updated/refreshed dynamically
[] call A3A_fnc_planning_cacheVehicles;

if (isNil "A3A_planning_closeEHAdded") then {
	A3A_planning_closeEHAdded = true;
	_display displayAddEventHandler ["Unload", {
		["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
		onMapSingleClick "";
		A3A_planning_closeEHAdded = nil;
	}];
};

private _uW = pixelGridNoUIScale * pixelW;
private _uH = pixelGridNoUIScale * pixelH;

private _colorMain = [
	profilenamespace getVariable ["GUI_BCG_RGB_R", 0.376],
	profilenamespace getVariable ["GUI_BCG_RGB_G", 0.125],
	profilenamespace getVariable ["GUI_BCG_RGB_B", 0.043],
	1
];

// Shared dark-theme colors for list/combo controls (fixes styling mismatch)
private _colorListBg = [0, 0, 0, 0.7];
private _colorListText = [1, 1, 1, 1];

// Helper: Translate squad list selection index to Antistasi classnames & prices
A3A_fnc_planning_getSquadDetails = {
	params ["_squadIndex", "_assignedGarageVeh"];

	private _squadType = "";
	private _idFormat = "";
	private _special = "";
	private _displayName = "";
	private _vehType = "";

	private _crewType = missionNamespace getVariable ["SDKMil", "I_G_Soldier_F"];
	if (isNil "_crewType" || {
		_crewType == "" || {
			!isClass (configFile >> "CfgVehicles" >> _crewType)
		}
	}) then {
		private _squadGroup = A3A_faction_reb getOrDefault ["groupSquad", []];
		if (count _squadGroup > 0) then {
			_crewType = _squadGroup # 0;
		};
	};
	if (isNil "_crewType" || {
		_crewType == "" || {
			!isClass (configFile >> "CfgVehicles" >> _crewType)
		}
	}) then {
		_crewType = "I_G_Soldier_F";
	};

	switch (_squadIndex) do {
		case 0: {
			private _rawSquad = A3A_faction_reb getOrDefault ["groupSquad", []];
			private _atSpec = A3A_faction_reb getOrDefault ["unitAT", ""];
			private _aaSpec = A3A_faction_reb getOrDefault ["unitAA", ""];
			private _cleanSquad = [];
			{
				if (_x != _atSpec && { _x != _aaSpec }) then {
					_cleanSquad pushBack _x;
				} else {
					_cleanSquad pushBack _crewType;
				};
			} forEach _rawSquad;
			_squadType = _cleanSquad;
			_idFormat = "Squad-";
			_displayName = "Infantry Squad";
		};
		case 1: {
			private _rawSquad = A3A_faction_reb getOrDefault ["groupMedium", []];
			private _atSpec = A3A_faction_reb getOrDefault ["unitAT", ""];
			private _aaSpec = A3A_faction_reb getOrDefault ["unitAA", ""];
			private _cleanSquad = [];
			{
				if (_x != _atSpec && { _x != _aaSpec }) then {
					_cleanSquad pushBack _x;
				} else {
					_cleanSquad pushBack _crewType;
				};
			} forEach _rawSquad;
			_squadType = _cleanSquad;
			_idFormat = "Tm-";
			_displayName = "Infantry Team";
		};
		case 2: {
			private _atSpec = A3A_faction_reb getOrDefault ["unitAT", _crewType];
			_squadType = [_atSpec, _atSpec, _atSpec, _atSpec];
			_idFormat = "AT-";
			_displayName = "AT Team";
		};
		case 3: {
			_squadType = A3A_faction_reb get "groupSniper";
			_idFormat = "Snpr-";
			_displayName = "Sniper Team";
		};
		case 4: {
			_squadType = A3A_faction_reb getOrDefault ["groupMG", []];
			if (count _squadType == 0) then {
				_squadType = [_crewType, _crewType];
				_special = "MG_FALLBACK";
			} else {
				_special = "MG";
			};
			_idFormat = "MG-";
			_displayName = "MG Team";
		};
		case 5: {
			_squadType = A3A_faction_reb getOrDefault ["groupMortar", []];
			if (count _squadType == 0) then {
				_squadType = [_crewType, _crewType];
				_special = "Mortar_FALLBACK";
			} else {
				_special = "Mortar";
			};
			_idFormat = "Mortar-";
			_displayName = "Mortar Team";
		};
		case 6: {
			private _vehCrewType = missionNamespace getVariable ["staticCrewReb", _crewType];
			_squadType = [_vehCrewType, _vehCrewType];
			_idFormat = "Tech-";
			_special = "VehicleSquad";
			_displayName = "Armed Technical (MG)";
			_vehType = A3A_planning_cachedVehicles getOrDefault ["LIGHT_ARMED", ""];
		};
		case 7: {
			private _vehCrewType = missionNamespace getVariable ["staticCrewReb", _crewType];
			_squadType = [_vehCrewType, _vehCrewType];
			_idFormat = "AT.Tech-";
			_special = "VehicleSquad";
			_displayName = "AT Technical (SPG/AT)";
			_vehType = A3A_planning_cachedVehicles getOrDefault ["AT", ""];
		};
		case 9: {
			private _vehCrewType = missionNamespace getVariable ["staticCrewReb", _crewType];
			_squadType = [_vehCrewType, _vehCrewType];
			_idFormat = "M.AA-";
			_special = "VehicleSquad";
			_displayName = "Anti-Air Vehicle";
			_vehType = A3A_planning_cachedVehicles getOrDefault ["AA", ""];
		};
		case 11: {
			private _vehCrewType = missionNamespace getVariable ["staticCrewReb", _crewType];
			_squadType = [_vehCrewType, _vehCrewType];
			_idFormat = "APC-";
			_special = "VehicleSquad";
			_displayName = "Armored APC";
			_vehType = A3A_planning_cachedVehicles getOrDefault ["APC", ""];
		};
		case 12: {
			private _vehCrewType = missionNamespace getVariable ["staticCrewReb", _crewType];
			_squadType = [_vehCrewType, _vehCrewType];
			_idFormat = "Tank-";
			_special = "VehicleSquad";
			_displayName = "Combat Tank";
			_vehType = A3A_planning_cachedVehicles getOrDefault ["TANK", ""];
		};
		case 13: {
			private _aaSpec = A3A_faction_reb getOrDefault ["unitAA", _crewType];
			_squadType = [_aaSpec, _aaSpec, _aaSpec, _aaSpec];
			_idFormat = "AA-";
			_displayName = "AA Team";
		};
	};

	// Calculate money and HR costs natively to guarantee correctness on clients
	private _money = 0;
	private _hr = 0;

	private _crewCost = server getVariable [_crewType, 0];

	if (_squadIndex in [0, 1, 2, 3, 4, 5, 13]) then {
		{
			_money = _money + (server getVariable [_x, 0]);
			_hr = _hr + 1;
		} forEach _squadType;

		// Apply 3.0x troop multiplier for strategic deploy costs
		_money = _money * 3;

		// Enforce squad-based minimums
		private _minCost = 250;
		switch (_squadIndex) do {
			case 0: { _minCost = 500; }; // Infantry Squad
			case 1: { _minCost = 250; }; // Infantry Team
			case 2: { _minCost = 500; }; // AT Team
			case 13: { _minCost = 500; }; // AA Team
			case 3: { _minCost = 300; }; // Sniper Team
			case 4: { _minCost = 350; }; // MG Team
			case 5: { _minCost = 600; }; // Mortar Team
		};
		_money = _money max _minCost;

		// if falling back to basic _crewType (because the faction config templates had empty arrays), 
		// add the static HMG/Mortar purchasing costs.
		if (_squadIndex == 4 && {
			count (A3A_faction_reb getOrDefault ["groupMG", []]) == 0
		}) then {
			private _staticMG = (A3A_faction_reb getOrDefault ["staticMGs", [""]]) # 0;
			private _mgCost = if (_staticMG != "") then {
				[_staticMG] call A3A_fnc_vehiclePrice
			} else {
				400
			};
			_money = _money + _mgCost;
		};
		if (_squadIndex == 5 && {
			count (A3A_faction_reb getOrDefault ["groupMortar", []]) == 0
		}) then {
			private _staticMortar = (A3A_faction_reb getOrDefault ["staticMortars", [""]]) # 0;
			private _mortarCost = if (_staticMortar != "") then {
				[_staticMortar] call A3A_fnc_vehiclePrice
			} else {
				700
			};
			_money = _money + _mortarCost;
		};
	} else {
		private _fnc_resolveVehiclePrice = {
			params ["_type", "_minPrice"];
			private _price = [_type] call A3A_fnc_vehiclePrice;
			if (isNil "_price" || { _price <= 0 }) then {
				_minPrice
			} else {
				_price max _minPrice
			};
		};

		switch (_squadIndex) do {
			case 6: {
				// Armed Technical (MG)
				private _vehCost = [_vehType, 1200] call _fnc_resolveVehiclePrice;
				_money = (2 * _crewCost) + _vehCost;
				_hr = 2;
			};
			case 7: {
				// AT Technical (SPG/AT)
				private _vehCost = [_vehType, 1800] call _fnc_resolveVehiclePrice;
				_money = (2 * _crewCost) + _vehCost;
				_hr = 2;
			};
			case 9: {
				// Anti-Air vehicle
				private _vehCost = [_vehType, 6000] call _fnc_resolveVehiclePrice;
				_money = (2 * _crewCost) + _vehCost;
				_hr = 2;
			};
			case 11: {
				// Armored APC
				private _vehCost = [_vehType, 10000] call _fnc_resolveVehiclePrice;
				_money = (2 * _crewCost) + _vehCost;
				_hr = 2;
			};
			case 12: {
				// Combat Tank
				private _vehCost = [_vehType, 20000] call _fnc_resolveVehiclePrice;
				_money = (2 * _crewCost) + _vehCost;
				_hr = 2;
			};
		};
	};

	[_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName]
};

// 1. Create or retrieve the ControlsGroup container (IDC 8000)
private _controlsGroup = _display displayCtrl 8000;
if (isNull _controlsGroup) then {
	_controlsGroup = _display ctrlCreate ["ScrtRscControlsGroup", 8000];
	_controlsGroup ctrlSetPosition [-0.4 * safeZoneW + safeZoneX, safeZoneY + 12 * _uH, 26 * _uW, safeZoneH - 12 * _uH];
	_controlsGroup ctrlSetFade 0;
	_controlsGroup ctrlCommit 0;

	    // Initialize Map mode
	A3A_planning_mapMode = "";
	A3A_planning_selectedStagingToMove = "";
	{
		private _mName = "A3A_planning_entry_" + _x;
		if (_mName in allMapMarkers) then {
			_mName setMarkerColorLocal "ColorGreen";
		};
	} forEach A3A_planning_entryPoints;

	    // --- TITLE ---
	private _ctrlTitle = _display ctrlCreate ["TextBase", 8010, _controlsGroup];
	_ctrlTitle ctrlSetPosition [1 * _uW, 0 * _uH, 22 * _uW, 1.5 * _uH];
	_ctrlTitle ctrlSetText "SIEGE & ATTACK PLANNING";
	_ctrlTitle ctrlSetFont "PuristaBold";
	_ctrlTitle ctrlSetFade 0;
	_ctrlTitle ctrlCommit 0;

	    // --- step 1: select TARGET ---
	private _ctrlBtnPlanTarget = _display ctrlCreate ["ButtonBase", 8015, _controlsGroup];
	_ctrlBtnPlanTarget ctrlSetPosition [1 * _uW, 2 * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnPlanTarget ctrlSetText "Plan Siege (Select Target)";
	_ctrlBtnPlanTarget ctrlSetBackgroundColor _colorMain;
	_ctrlBtnPlanTarget ctrlSetFade 0;
	_ctrlBtnPlanTarget ctrlCommit 0;
	_ctrlBtnPlanTarget ctrlAddEventHandler ["ButtonClick", {
		A3A_planning_mapMode = "TARGET";
		["Planning Target", "Click on the map on the right to select the enemy target outpost or base.", false] call A3A_fnc_planning_showNotification;

		["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
		[
			"A3A_planning_mapClick",
			"onMapSingleClick",
			{
				[_pos] call A3A_fnc_planning_onMapClick;
			}
		] call BIS_fnc_addStackedEventHandler;
	}];

	private _ctrlObjText = _display ctrlCreate ["TextBase", 8011, _controlsGroup];
	_ctrlObjText ctrlSetPosition [1 * _uW, 4.2 * _uH, 22 * _uW, 1.5 * _uH];
	_ctrlObjText ctrlSetFont "PuristaMedium";
	_ctrlObjText ctrlSetTextColor [1, 0.8, 0.5, 1];
	_ctrlObjText ctrlSetFade 0;
	_ctrlObjText ctrlCommit 0;

	    // --- step 2: CONFIGURE ENTRY POINTS ---
	private _ctrlBtnEntryAdd = _display ctrlCreate ["ButtonBase", 8016, _controlsGroup];
	_ctrlBtnEntryAdd ctrlSetPosition [1 * _uW, 6 * _uH, 6.8 * _uW, 2 * _uH];
	_ctrlBtnEntryAdd ctrlSetText "Add Staging";
	_ctrlBtnEntryAdd ctrlSetBackgroundColor _colorMain;
	_ctrlBtnEntryAdd ctrlSetFade 0;
	_ctrlBtnEntryAdd ctrlCommit 0;
	_ctrlBtnEntryAdd ctrlAddEventHandler ["ButtonClick", {
		A3A_planning_mapMode = "STAGING_ADD";
		A3A_planning_selectedStagingToMove = "";
		{
			private _mName = "A3A_planning_entry_" + _x;
			if (_mName in allMapMarkers) then {
				_mName setMarkerColorLocal "ColorGreen";
			};
		} forEach A3A_planning_entryPoints;

		["Staging Addition", "Click on the map to place a new staging marker (Alpha, Beta, Gamma, Delta).", false] call A3A_fnc_planning_showNotification;

		["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
		[
			"A3A_planning_mapClick",
			"onMapSingleClick",
			{
				[_pos] call A3A_fnc_planning_onMapClick;
			}
		] call BIS_fnc_addStackedEventHandler;
	}];

	private _ctrlBtnEntryMove = _display ctrlCreate ["ButtonBase", 8017, _controlsGroup];
	_ctrlBtnEntryMove ctrlSetPosition [8.8 * _uW, 6 * _uH, 6.8 * _uW, 2 * _uH];
	_ctrlBtnEntryMove ctrlSetText "Move Staging";
	_ctrlBtnEntryMove ctrlSetBackgroundColor _colorMain;
	_ctrlBtnEntryMove ctrlSetFade 0;
	_ctrlBtnEntryMove ctrlCommit 0;
	_ctrlBtnEntryMove ctrlAddEventHandler ["ButtonClick", {
		A3A_planning_mapMode = "STAGING_MOVE";
		A3A_planning_selectedStagingToMove = "";
		{
			private _mName = "A3A_planning_entry_" + _x;
			if (_mName in allMapMarkers) then {
				_mName setMarkerColorLocal "ColorGreen";
			};
		} forEach A3A_planning_entryPoints;

		["Staging Movement", "Click near an existing staging marker to select it, then click anywhere on the map to move it.", false] call A3A_fnc_planning_showNotification;

		["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
		[
			"A3A_planning_mapClick",
			"onMapSingleClick",
			{
				[_pos] call A3A_fnc_planning_onMapClick;
			}
		] call BIS_fnc_addStackedEventHandler;
	}];

	private _ctrlBtnEntryDel = _display ctrlCreate ["ButtonBase", 8018, _controlsGroup];
	_ctrlBtnEntryDel ctrlSetPosition [16.6 * _uW, 6 * _uH, 6.4 * _uW, 2 * _uH];
	_ctrlBtnEntryDel ctrlSetText "Remove Staging";
	_ctrlBtnEntryDel ctrlSetBackgroundColor [0.6, 0.1, 0.1, 1];
	_ctrlBtnEntryDel ctrlSetFade 0;
	_ctrlBtnEntryDel ctrlCommit 0;
	_ctrlBtnEntryDel ctrlAddEventHandler ["ButtonClick", {
		A3A_planning_mapMode = "STAGING_DELETE";
		A3A_planning_selectedStagingToMove = "";
		{
			private _mName = "A3A_planning_entry_" + _x;
			if (_mName in allMapMarkers) then {
				_mName setMarkerColorLocal "ColorRed";
			};
		} forEach A3A_planning_entryPoints;

		["Staging Deletion", "Click on a red staging marker on the map to remove it.", false] call A3A_fnc_planning_showNotification;

		["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
		[
			"A3A_planning_mapClick",
			"onMapSingleClick",
			{
				[_pos] call A3A_fnc_planning_onMapClick;
			}
		] call BIS_fnc_addStackedEventHandler;
	}];

	    // --- step 3: RECRUIT and QUEUE FORCES ---
	    // Squad selection ListBox (Multi-row scrollable list)
	private _ctrlSquadCombo = _display ctrlCreate ["RscListBox", 8020, _controlsGroup];
	_ctrlSquadCombo ctrlSetPosition [1 * _uW, 9 * _uH, 22 * _uW, 9.5 * _uH];
	_ctrlSquadCombo ctrlSetBackgroundColor _colorListBg;
	_ctrlSquadCombo ctrlSetTextColor _colorListText;
	_ctrlSquadCombo ctrlSetFont "PuristaLight";
	_ctrlSquadCombo ctrlSetFade 0;
	_ctrlSquadCombo ctrlCommit 0;
	_ctrlSquadCombo ctrlAddEventHandler ["LBSelChanged", {
		private _display = ctrlParent (_this select 0);
		private _selIdx = lbCurSel (_this select 0);
		if (_selIdx != -1) then {
			private _dataVal = (_this select 0) lbData _selIdx;
			private _sIndex = parseNumber _dataVal;
			A3A_planning_selectedSquadIndex = _sIndex;
			[_display] call A3A_fnc_planning_ui;
		};
	}];

	    // Staging area dropdown
	private _ctrlSquadEntryCombo = _display ctrlCreate ["BaseComboBox", 8022, _controlsGroup];
	_ctrlSquadEntryCombo ctrlSetPosition [1 * _uW, 19 * _uH, 22 * _uW, 2 * _uH];
	_ctrlSquadEntryCombo ctrlSetBackgroundColor _colorListBg;
	_ctrlSquadEntryCombo ctrlSetTextColor _colorListText;
	_ctrlSquadEntryCombo ctrlSetFont "PuristaLight";
	_ctrlSquadEntryCombo ctrlShow true;
	_ctrlSquadEntryCombo ctrlSetFade 0;
	_ctrlSquadEntryCombo ctrlCommit 0;

	    // HQ Garage vehicle dropdown (hidden)
	private _ctrlVehLabel = _display ctrlCreate ["TextBase", 8031, _controlsGroup];
	_ctrlVehLabel ctrlSetPosition [1 * _uW, 21.5 * _uH, 22 * _uW, 1.5 * _uH];
	_ctrlVehLabel ctrlSetText "Available Vehicle Configs:";
	_ctrlVehLabel ctrlSetFont "PuristaLight";
	_ctrlVehLabel ctrlShow false;
	_ctrlVehLabel ctrlSetFade 0;
	_ctrlVehLabel ctrlCommit 0;

	private _ctrlVehCombo = _display ctrlCreate ["BaseComboBox", 8030, _controlsGroup];
	_ctrlVehCombo ctrlSetPosition [1 * _uW, 23 * _uH, 22 * _uW, 2 * _uH];
	_ctrlVehCombo ctrlSetBackgroundColor _colorListBg;
	_ctrlVehCombo ctrlSetTextColor _colorListText;
	_ctrlVehCombo ctrlSetFont "PuristaLight";
	_ctrlVehCombo ctrlShow false;
	_ctrlVehCombo ctrlSetFade 0;
	_ctrlVehCombo ctrlCommit 0;

	    // Queue button
	private _ctrlBtnQueue = _display ctrlCreate ["ButtonBase", 8023, _controlsGroup];
	_ctrlBtnQueue ctrlSetPosition [1 * _uW, 21.5 * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnQueue ctrlSetText "Queue Squad";
	_ctrlBtnQueue ctrlSetBackgroundColor _colorMain;
	_ctrlBtnQueue ctrlSetFade 0;
	_ctrlBtnQueue ctrlCommit 0;
	_ctrlBtnQueue ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);

		private _entryCombo = _display displayCtrl 8022;
		private _entry = _entryCombo lbData (lbCurSel _entryCombo);

		if (_entry == "") exitWith {
			["Denied", "You must set and select a deployment marker/staging area first.", true] call A3A_fnc_planning_showNotification;
		};

		private _maxSiegeSquads = missionNamespace getVariable ["A3A_tweak_maxSiegeSquads", 10];
		if (count A3A_planning_queue >= _maxSiegeSquads) exitWith {
			["Limit Reached", format ["You cannot queue more than %1 squads for a single siege.", _maxSiegeSquads], true] call A3A_fnc_planning_showNotification;
		};

		private _details = [A3A_planning_selectedSquadIndex, ""] call A3A_fnc_planning_getSquadDetails;
		_details params ["_squadType", "_idFormat", "_special", "_money", "_hr", "_vehType", "_displayName"];

		A3A_planning_queue pushBack [_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName, _entry];
		[_display] call A3A_fnc_planning_ui;
	}];

	    // --- QUEUED list ---
	private _ctrlQueueList = _display ctrlCreate ["RscListBox", 8014, _controlsGroup];
	_ctrlQueueList ctrlSetPosition [1 * _uW, 24 * _uH, 22 * _uW, 6 * _uH];
	_ctrlQueueList ctrlSetBackgroundColor _colorListBg;
	_ctrlQueueList ctrlSetTextColor _colorListText;
	_ctrlQueueList ctrlSetFade 0;
	_ctrlQueueList ctrlCommit 0;

	private _ctrlBtnRemove = _display ctrlCreate ["ButtonBase", 8024, _controlsGroup];
	_ctrlBtnRemove ctrlSetPosition [1 * _uW, 30.5 * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnRemove ctrlSetText "Remove Selected";
	_ctrlBtnRemove ctrlSetBackgroundColor _colorMain;
	_ctrlBtnRemove ctrlSetFade 0;
	_ctrlBtnRemove ctrlCommit 0;
	_ctrlBtnRemove ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		private _list = _display displayCtrl 8014;
		private _selIdx = lbCurSel _list;
		if (_selIdx != -1) then {
			A3A_planning_queue deleteAt _selIdx;
			[_display] call A3A_fnc_planning_ui;
		};
	}];

	    // --- COSTS & COMMENCE ---
	private _ctrlCapChk = _display ctrlCreate ["RscCheckBox", 8042, _controlsGroup];
	_ctrlCapChk ctrlSetPosition [1 * _uW, 33 * _uH, 2 * _uW, 2 * _uH];
	_ctrlCapChk ctrlSetFade 0;
	_ctrlCapChk ctrlCommit 0;
	    _ctrlCapChk cbSetChecked true;

	private _ctrlCapLabel = _display ctrlCreate ["TextBase", 8043, _controlsGroup];
	_ctrlCapLabel ctrlSetPosition [3.5 * _uW, 33 * _uH, 19.5 * _uW, 2 * _uH];
	_ctrlCapLabel ctrlSetText "Automatically Capture Objective";
	_ctrlCapLabel ctrlSetFont "PuristaLight";
	_ctrlCapLabel ctrlSetFade 0;
	_ctrlCapLabel ctrlCommit 0;

	private _ctrlCostLabel = _display ctrlCreate ["RscStructuredText", 8025, _controlsGroup];
	_ctrlCostLabel ctrlSetPosition [1 * _uW, 35.5 * _uH, 22 * _uW, 5.5 * _uH];
	_ctrlCostLabel ctrlSetFont "PuristaLight";
	_ctrlCostLabel ctrlSetFade 0;
	_ctrlCostLabel ctrlCommit 0;

	private _ctrlBtnCommence = _display ctrlCreate ["ButtonBase", 8026, _controlsGroup];
	_ctrlBtnCommence ctrlSetPosition [1 * _uW, 41.5 * _uH, 22 * _uW, 3 * _uH];
	_ctrlBtnCommence ctrlSetText "Commence Siege";
	_ctrlBtnCommence ctrlSetBackgroundColor [0.6, 0.1, 0.1, 1];
	_ctrlBtnCommence ctrlSetFade 0;
	_ctrlBtnCommence ctrlCommit 0;

	private _uiCooldownSecs = missionNamespace getVariable ["A3A_tweak_siegeCooldown", 600];
	if (_uiCooldownSecs > 0) then {
		private _lastTime = missionNamespace getVariable ["A3A_planning_lastCommenceTime", -9999];
		private _elapsed = time - _lastTime;
		if (_elapsed < _uiCooldownSecs) then {
			private _remSecs = ceil (_uiCooldownSecs - _elapsed);
			private _remMin = floor (_remSecs / 60);
			private _remSec = _remSecs % 60;
			private _timeStr = if (_remMin > 0) then { format ["%1m %2s", _remMin, _remSec] } else { format ["%1s", _remSec] };
			_ctrlBtnCommence ctrlSetTooltip format ["Siege Planner is on cooldown (%1 remaining)", _timeStr];
		};
	};

	private _ctrlBtnClear = _display ctrlCreate ["ButtonBase", 8027, _controlsGroup];
	_ctrlBtnClear ctrlSetPosition [1 * _uW, 45 * _uH, 22 * _uW, 2.5 * _uH];
	_ctrlBtnClear ctrlSetText "Clear Plan";
	_ctrlBtnClear ctrlSetBackgroundColor [0.35, 0.35, 0.35, 1];
	_ctrlBtnClear ctrlSetFade 0;
	_ctrlBtnClear ctrlCommit 0;
	_ctrlBtnClear ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		[true] call A3A_fnc_planning_localCleanupMarkers;
		["Plan Cleared", "The current siege plan and map markers have been cleared.", false] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	}];
	_ctrlBtnCommence ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		if (A3A_planning_objective == "") exitWith {
			["Denied", "You must select a target objective first.", true] call A3A_fnc_planning_showNotification;
		};
		if (count A3A_planning_queue == 0) exitWith {
			["Denied", "You must queue at least one squad to deploy.", true] call A3A_fnc_planning_showNotification;
		};

		// Check configurable siege cooldown
		private _cooldownSecs = missionNamespace getVariable ["A3A_tweak_siegeCooldown", 600];
		if (_cooldownSecs > 0) then {
			private _lastTime = missionNamespace getVariable ["A3A_planning_lastCommenceTime", -9999];
			private _elapsed = time - _lastTime;
			if (_elapsed < _cooldownSecs) exitWith {
				private _remSecs = ceil (_cooldownSecs - _elapsed);
				private _remMin = floor (_remSecs / 60);
				private _remSec = _remSecs % 60;
				private _timeStr = if (_remMin > 0) then { format ["%1m %2s", _remMin, _remSec] } else { format ["%1s", _remSec] };
				["Cooldown Active", format ["Siege Planner is on cooldown. Please wait %1 before launching another operation.", _timeStr], true] call A3A_fnc_planning_showNotification;
			};
		};
		private _lastTimeCheck = missionNamespace getVariable ["A3A_planning_lastCommenceTime", -9999];
		if (_cooldownSecs > 0 && { (time - _lastTimeCheck) < _cooldownSecs }) exitWith {};

		private _totalMoney = 0;
		private _totalHR = 0;
		{
			_totalMoney = _totalMoney + (_x select 3);
			_totalHR = _totalHR + (_x select 4);
		} forEach A3A_planning_queue;

		private _money = server getVariable "resourcesFIA";
		private _hr = server getVariable "hr";

		if (_money < _totalMoney) exitWith {
			["Denied", "You do not have enough faction money to deploy this force.", true] call A3A_fnc_planning_showNotification;
		};
		if (_hr < _totalHR) exitWith {
			["Denied", "You do not have enough faction HR to deploy this force.", true] call A3A_fnc_planning_showNotification;
		};

		private _addHC = false;
		private _autoCapture = cbChecked (_display displayCtrl 8042);
		private _queueCopy = +A3A_planning_queue;

		private _entryPositions = [];
		{
			private _mName = "A3A_planning_entry_" + _x;
			private _pos = getMarkerPos _mName;
			if (_pos isNotEqualTo [0, 0, 0]) then {
				_entryPositions pushBack [_x, _pos];
			};
		} forEach A3A_planning_entryPoints;

		closeDialog 0;

		["Siege Commenced", "All recruited squads have departed HQ. Watch for radio progress transmissions!", false] call A3A_fnc_planning_showNotification;

		// Record and broadcast commence timestamp for cooldown tracking
		A3A_planning_lastCommenceTime = time;
		publicVariable "A3A_planning_lastCommenceTime";

		A3A_planning_queue = [];

		["DEPLOY", [_totalMoney, _totalHR, clientOwner, _addHC, _queueCopy, _autoCapture, _entryPositions, A3A_planning_objective]] remoteExec ["A3A_fnc_planning_execute", 2];
	}];

	    // Dummy control
	private _ctrlDummy = _display ctrlCreate ["TextBase", 8099, _controlsGroup];
	_ctrlDummy ctrlSetPosition [1 * _uW, 48 * _uH, 22 * _uW, 0.1 * _uH];
	_ctrlDummy ctrlSetText "";
	_ctrlDummy ctrlSetFade 1;
	_ctrlDummy ctrlCommit 0;
};

// 2. Populate and Refresh Controls
// Handle Area of Operations (AO) visualization
if (A3A_planning_objective != "") then {
	private _targetPos = getMarkerPos A3A_planning_objective;
	if (_targetPos distance2D [0, 0, 0] > 100) then {
		private _aoMarker = "A3A_planning_AO";
		if (_aoMarker in allMapMarkers) then {
			_aoMarker setMarkerPosLocal _targetPos;
		} else {
			private _m = createMarkerLocal [_aoMarker, _targetPos];
			_m setMarkerShapeLocal "ELLIPSE";
			_m setMarkerSizeLocal [500, 500];
			_m setMarkerColorLocal "ColorRed";
			_m setMarkerBrushLocal "GRID";
		};
	};
} else {
	if ("A3A_planning_AO" in allMapMarkers) then {
		deleteMarkerLocal "A3A_planning_AO";
	};
};

private _ctrlObjText = _display displayCtrl 8011;
private _targetName = "Target: None Selected";
if (A3A_planning_objective != "") then {
	private _name = markerText ("Dum" + A3A_planning_objective);
	if (_name == "") then {
		_name = A3A_planning_objective;
	};
	_targetName = format ["Target: %1", _name];
};
_ctrlObjText ctrlSetText _targetName;

// Refresh Staging dropdown
private _ctrlSquadEntryCombo = _display displayCtrl 8022;
lbClear _ctrlSquadEntryCombo;

private _epIdx = 0;
{
	_ctrlSquadEntryCombo lbAdd _x;
	_ctrlSquadEntryCombo lbSetData [_epIdx, _x];
	_epIdx = _epIdx + 1;
} forEach A3A_planning_entryPoints;

// Restore staging selection
if (count A3A_planning_entryPoints > 0) then {
	private _squadSel = A3A_planning_entryPoints find A3A_planning_selectedSquadEntry;
	if (_squadSel != -1) then {
		_ctrlSquadEntryCombo lbSetCurSel _squadSel;
	} else {
		_ctrlSquadEntryCombo lbSetCurSel 0;
	};
};

// Populate squad type listbox
private _ctrlSquadCombo = _display displayCtrl 8020;
lbClear _ctrlSquadCombo;
private _available = A3A_planning_cachedVehicles getOrDefault ["MENU_ITEMS", []];

private _idx = 0;
private _selectedRow = 0;
{
	_x params ["_label", "_dataId"];
	_ctrlSquadCombo lbAdd _label;
	_ctrlSquadCombo lbSetData [_idx, _dataId];
	if (parseNumber _dataId == A3A_planning_selectedSquadIndex) then {
		_selectedRow = _idx;
	};
	_idx = _idx + 1;
} forEach _available;

_ctrlSquadCombo lbSetCurSel _selectedRow;

// The garage crew vehicle selector has been removed (vehicle crew Squad no longer exists).
// Keep the controls hidden at all times so any old IDC references don't error.
private _ctrlVehLabel = _display displayCtrl 8031;
private _ctrlVehCombo = _display displayCtrl 8030;
_ctrlVehLabel ctrlShow false;
_ctrlVehCombo ctrlShow false;

// crew vehicle selector is permanently hidden (vehicle crew Squad removed).

// Layout: crew selector removed, so offset is always 0
private _crewOffset = 0;

private _ctrlBtnQueue = _display displayCtrl 8023;
_ctrlBtnQueue ctrlSetPosition [1 * _uW, (21.5 + _crewOffset) * _uH, 22 * _uW, 2 * _uH];
_ctrlBtnQueue ctrlCommit 0;

private _ctrlQueueList = _display displayCtrl 8014;
_ctrlQueueList ctrlSetPosition [1 * _uW, (24 + _crewOffset) * _uH, 22 * _uW, 6 * _uH];
_ctrlQueueList ctrlCommit 0;

private _ctrlBtnRemove = _display displayCtrl 8024;
_ctrlBtnRemove ctrlSetPosition [1 * _uW, (30.5 + _crewOffset) * _uH, 22 * _uW, 2 * _uH];
_ctrlBtnRemove ctrlCommit 0;

private _ctrlCapChk = _display displayCtrl 8042;
_ctrlCapChk ctrlSetPosition [1 * _uW, (33 + _crewOffset) * _uH, 2 * _uW, 2 * _uH];
_ctrlCapChk ctrlCommit 0;

private _ctrlCapLabel = _display displayCtrl 8043;
_ctrlCapLabel ctrlSetPosition [3.5 * _uW, (33 + _crewOffset) * _uH, 19.5 * _uW, 2 * _uH];
_ctrlCapLabel ctrlCommit 0;

private _ctrlCostLabel = _display displayCtrl 8025;
_ctrlCostLabel ctrlSetPosition [1 * _uW, (35.5 + _crewOffset) * _uH, 22 * _uW, 5.5 * _uH];
_ctrlCostLabel ctrlCommit 0;

private _ctrlBtnCommence = _display displayCtrl 8026;
_ctrlBtnCommence ctrlSetPosition [1 * _uW, (41.5 + _crewOffset) * _uH, 22 * _uW, 3 * _uH];
_ctrlBtnCommence ctrlCommit 0;

private _ctrlBtnClear = _display displayCtrl 8027;
_ctrlBtnClear ctrlSetPosition [1 * _uW, (45 + _crewOffset) * _uH, 22 * _uW, 2.5 * _uH];
_ctrlBtnClear ctrlCommit 0;

private _ctrlDummy = _display displayCtrl 8099;
_ctrlDummy ctrlSetPosition [1 * _uW, (48 + _crewOffset) * _uH, 22 * _uW, 0.1 * _uH];
_ctrlDummy ctrlCommit 0;

// Workflow step checks
private _hasObjective = (A3A_planning_objective != "");
private _hasStaging = (count A3A_planning_entryPoints > 0);
private _hasQueue = (count A3A_planning_queue > 0);

// step 2 enablement (Add/move/Remove Staging)
private _ctrlBtnEntryAdd = _display displayCtrl 8016;
private _ctrlBtnEntryMove = _display displayCtrl 8017;
private _ctrlBtnEntryDel = _display displayCtrl 8018;
_ctrlBtnEntryAdd ctrlEnable _hasObjective;
_ctrlBtnEntryMove ctrlEnable _hasObjective;
_ctrlBtnEntryDel ctrlEnable (_hasObjective && {
	_hasStaging
});

if (!_hasObjective) then {
	_ctrlBtnEntryAdd ctrlSetTooltip "You must select a target objective first.";
	_ctrlBtnEntryMove ctrlSetTooltip "You must select a target objective first.";
	_ctrlBtnEntryDel ctrlSetTooltip "You must select a target objective first.";
} else {
	_ctrlBtnEntryAdd ctrlSetTooltip "";
	_ctrlBtnEntryMove ctrlSetTooltip "";
	_ctrlBtnEntryDel ctrlSetTooltip "";
};

// step 3 enablement (Recruit/Squad combo list and entry/veh dropdowns)
private _ctrlSquadCombo = _display displayCtrl 8020;
private _ctrlSquadEntryCombo = _display displayCtrl 8022;
private _ctrlVehCombo = _display displayCtrl 8030;

_ctrlSquadCombo ctrlEnable _hasStaging;
_ctrlSquadEntryCombo ctrlEnable _hasStaging;
_ctrlVehCombo ctrlEnable _hasStaging;

if (!_hasStaging) then {
	_ctrlSquadCombo ctrlSetTooltip "You must configure at least one staging area first.";
	_ctrlSquadEntryCombo ctrlSetTooltip "You must configure at least one staging area first.";
} else {
	_ctrlSquadCombo ctrlSetTooltip "";
	_ctrlSquadEntryCombo ctrlSetTooltip "";
};

private _ctrlHCChk = _display displayCtrl 8040;
private _ctrlHCLabel = _display displayCtrl 8041;
_ctrlHCChk ctrlEnable _hasStaging;
_ctrlHCLabel ctrlEnable _hasStaging;

private _ctrlCapChk = _display displayCtrl 8042;
private _ctrlCapLabel = _display displayCtrl 8043;
_ctrlCapChk ctrlEnable _hasStaging;
_ctrlCapLabel ctrlEnable _hasStaging;

// High Command and Queue limit checks
private _maxSiegeSquads = missionNamespace getVariable ["A3A_tweak_maxSiegeSquads", 10];
private _currentHcCount = count (hcAllGroups player);
private _maxHcLimit = if (player call A3A_fnc_isMember) then {
	10
} else {
	6
};

private _queueCount = count A3A_planning_queue;
private _canQueue = (_queueCount < _maxSiegeSquads) && (_currentHcCount + _queueCount < _maxHcLimit) && _hasStaging;
_ctrlBtnQueue ctrlEnable _canQueue;

if (!_canQueue) then {
	private _tooltip = "";
	if (!_hasStaging) then {
		_tooltip = "You must configure at least one staging area first.";
	} else {
		if (_queueCount >= _maxSiegeSquads) then {
			_tooltip = format ["Deployment limit reached: Maximum of %1 squads per siege.", _maxSiegeSquads];
		} else {
			_tooltip = "High Command limit reached: Cannot recruit more squads.";
		};
	};
	_ctrlBtnQueue ctrlSetTooltip _tooltip;
} else {
	_ctrlBtnQueue ctrlSetTooltip "";
};

// step 4 enablement (Commence Siege)
private _ctrlBtnCommence = _display displayCtrl 8026;
private _canCommence = _hasObjective && _hasStaging && _hasQueue;
_ctrlBtnCommence ctrlEnable _canCommence;

if (!_canCommence) then {
	private _commenceTooltip = "";
	if (!_hasObjective) then {
		_commenceTooltip = "You must select a target objective first.";
	} else {
		if (!_hasStaging) then {
			_commenceTooltip = "You must configure at least one staging area first.";
		} else {
			_commenceTooltip = "You must queue at least one squad to commence the siege.";
		};
	};
	_ctrlBtnCommence ctrlSetTooltip _commenceTooltip;
} else {
	_ctrlBtnCommence ctrlSetTooltip "";
};

private _ctrlBtnClear = _display displayCtrl 8027;
_ctrlBtnClear ctrlEnable _hasObjective;
if (!_hasObjective) then {
	_ctrlBtnClear ctrlSetTooltip "No active plan to clear.";
} else {
	_ctrlBtnClear ctrlSetTooltip "";
};

// Update Queue list box
lbClear _ctrlQueueList;
private _totalMoney = 0;
private _totalHR = 0;

{
	_x params ["_type", "_id", "_special", "_costMoney", "_costHR", "_veh", "_name", "_entry"];
	_ctrlQueueList lbAdd (format ["%1 (%2 € / %3 HR) - Sp: %4", _name, _costMoney, _costHR, _entry]);
	_totalMoney = _totalMoney + _costMoney;
	_totalHR = _totalHR + _costHR;
} forEach A3A_planning_queue;

// Update Cumulative Costs text
private _costText = format [
	"<t size='1.1'>CUMULATIVE COSTS</t><br/>HR Required: <t color='#84B062'>%1 HR</t><br/>Money Cost: <t color='#E3DCBE'>%2 €</t><br/>%3/%4 Squads Deployed<br/>HC Slots: %5 / %6 (Limit: %6)",
	_totalHR,
	_totalMoney,
	_queueCount,
	_maxSiegeSquads,
	_currentHcCount + _queueCount,
	_maxHcLimit
];
_ctrlCostLabel ctrlSetStructuredText parseText _costText;
_ctrlCostLabel ctrlCommit 0;

if (A3A_planning_assaultStarted) then {
	private _ctrlBtnPlanTarget = _display displayCtrl 8015;
	if (!isNull _ctrlBtnPlanTarget) then {
		_ctrlBtnPlanTarget ctrlEnable false;
		_ctrlBtnPlanTarget ctrlSetTooltip "An assault is currently in progress.";
	};

	private _ctrlBtnEntryAdd = _display displayCtrl 8016;
	private _ctrlBtnEntryMove = _display displayCtrl 8017;
	private _ctrlBtnEntryDel = _display displayCtrl 8018;
	if (!isNull _ctrlBtnEntryAdd) then {
		_ctrlBtnEntryAdd ctrlEnable false;
		_ctrlBtnEntryAdd ctrlSetTooltip "An assault is currently in progress.";
	};
	if (!isNull _ctrlBtnEntryMove) then {
		_ctrlBtnEntryMove ctrlEnable false;
		_ctrlBtnEntryMove ctrlSetTooltip "An assault is currently in progress.";
	};
	if (!isNull _ctrlBtnEntryDel) then {
		_ctrlBtnEntryDel ctrlEnable false;
		_ctrlBtnEntryDel ctrlSetTooltip "An assault is currently in progress.";
	};

	private _ctrlSquadCombo = _display displayCtrl 8020;
	private _ctrlSquadEntryCombo = _display displayCtrl 8022;
	private _ctrlVehCombo = _display displayCtrl 8030;
	private _ctrlBtnQueue = _display displayCtrl 8023;
	private _ctrlQueueList = _display displayCtrl 8014;
	private _ctrlBtnRemove = _display displayCtrl 8024;
	private _ctrlHCChk = _display displayCtrl 8040;
	private _ctrlCapChk = _display displayCtrl 8042;
	private _ctrlBtnCommence = _display displayCtrl 8026;
	private _ctrlBtnClear = _display displayCtrl 8027;

	if (!isNull _ctrlSquadCombo) then {
		_ctrlSquadCombo ctrlEnable false;
	};
	if (!isNull _ctrlSquadEntryCombo) then {
		_ctrlSquadEntryCombo ctrlEnable false;
	};
	if (!isNull _ctrlVehCombo) then {
		_ctrlVehCombo ctrlEnable false;
	};
	if (!isNull _ctrlBtnQueue) then {
		_ctrlBtnQueue ctrlEnable false;
	};
	if (!isNull _ctrlQueueList) then {
		_ctrlQueueList ctrlEnable false;
	};
	if (!isNull _ctrlBtnRemove) then {
		_ctrlBtnRemove ctrlEnable false;
	};
	if (!isNull _ctrlHCChk) then {
		_ctrlHCChk ctrlEnable false;
	};
	if (!isNull _ctrlCapChk) then {
		_ctrlCapChk ctrlEnable false;
	};
	if (!isNull _ctrlBtnCommence) then {
		_ctrlBtnCommence ctrlEnable false;
		_ctrlBtnCommence ctrlSetTooltip "An assault is currently in progress.";
	};
	if (!isNull _ctrlBtnClear) then {
		_ctrlBtnClear ctrlEnable false;
		_ctrlBtnClear ctrlSetTooltip "An assault is currently in progress.";
	};
};
// Re-adjust controls group to force recalculation of the vertical scroll range
private _currentPos = ctrlPosition _controlsGroup;
_controlsGroup ctrlSetPosition [_currentPos # 0, _currentPos # 1, _currentPos # 2, safeZoneH - 12 * _uH];
_controlsGroup ctrlCommit 0;