/*
	    fn_planning_ui.sqf
	    Builds, populates, and manages the redesigned Siege Planning Rework tab dynamically.
	    guided workflow: Target Selection -> Staging Areas (Entry Points) -> Squad Queue & Assignment -> Commencement.
*/

disableSerialization;
params [["_display", findDisplay 60000, [displayNull]]];

if (isNull _display) exitWith {};

// Ensure vehicle availability cache is updated/refreshed dynamically
[] call A3A_fnc_planning_cacheVehicles;

private _activeGroupCount = if (isNil "A3A_planning_activeGroups") then { 0 } else { { !isNull _x && { { alive _x } count (units _x) > 0 } } count A3A_planning_activeGroups };
private _activeUnitCount = if (isNil "A3A_planning_activeGroups") then { 0 } else {
	private _cnt = 0;
	{ if (!isNull _x) then { _cnt = _cnt + ({ alive _x } count (units _x)); }; } forEach A3A_planning_activeGroups;
	_cnt
};
private _activeStagingCount = count (missionNamespace getVariable ["A3A_planning_entryPoints", []]);
diag_log format ["[A3A Planning Diagnostics] UI opened. Target: '%1' | Active Siege Groups: %2 | Active Siege Units: %3 | Active Staging Points: %4", A3A_planning_objective, _activeGroupCount, _activeUnitCount, _activeStagingCount];

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
private _isReinforceMode = call A3A_fnc_planning_isSiegeActive;

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
		case 14: {
			// Vehicle Crew — garage vehicle assigned via _assignedGarageVeh param.
			// Friendly crew is auto-generated at spawn time; no infantry classnames stored in _squadType.
			_vehType = _assignedGarageVeh;
			_idFormat = "Crew-";
			_special = "GarageCrew";
			_displayName = "Vehicle Crew";
			_squadType = [];
		};
	};

	// Calculate money and HR costs natively to derive directly from Antistasi economy
	private _money = 0;
	private _hr = 0;
	private _deployMultiplier = missionNamespace getVariable ["A3A_tweak_siegeDeploymentMultiplier", 1.25];

	// Helper to resolve unit cost safely from server variables with fallback
	private _fnc_getUnitCost = {
		params ["_unitKey"];
		if (isNil "_unitKey" || { _unitKey == "" }) exitWith { 15 };
		private _cost = server getVariable _unitKey;
		if (isNil "_cost" || { _cost <= 0 }) then {
			private _rifleKey = A3A_faction_reb getOrDefault ["unitRifle", "unitRifle"];
			_cost = server getVariable [_rifleKey, 15];
		};
		if (isNil "_cost" || { _cost <= 0 }) then { _cost = 15; };
		_cost
	};

	private _crewUnitCost = [A3A_faction_reb getOrDefault ["unitCrew", "unitCrew"]] call _fnc_getUnitCost;

	// Helper to resolve vehicle or static asset price with priority:
	// 1. Native Antistasi vehicle price (A3A_fnc_vehiclePrice)
	// 2. Emergency fallback ONLY if price is <= 0 or nil
	private _fnc_resolveNativeVehiclePrice = {
		params ["_type", "_emergencyFallback"];
		private _price = 0;
		if (!isNil "_type" && { _type != "" } && { !isNil "A3A_fnc_vehiclePrice" }) then {
			_price = [_type] call A3A_fnc_vehiclePrice;
		};
		if (isNil "_price" || { _price <= 0 }) then {
			_price = _emergencyFallback;
		};
		_price
	};

	if (_squadIndex in [0, 1, 2, 3, 4, 5, 13]) then {
		// --- INFANTRY SQUADS & TEAMS ---
		private _rawUnitCostSum = 0;
		{
			private _uCost = [_x] call _fnc_getUnitCost;
			_rawUnitCostSum = _rawUnitCostSum + _uCost;
			_hr = _hr + 1;
		} forEach _squadType;

		_money = _rawUnitCostSum;

		// Include static weapon prices for MG and Mortar Teams
		if (_squadIndex == 4) then {
			private _staticMGs = A3A_faction_reb getOrDefault ["staticMGs", []];
			private _staticMGClass = if (count _staticMGs > 0) then { _staticMGs select 0 } else { "" };
			private _mgPrice = [_staticMGClass, 300] call _fnc_resolveNativeVehiclePrice;
			_money = _money + _mgPrice;
		};

		if (_squadIndex == 5) then {
			private _staticMortars = A3A_faction_reb getOrDefault ["staticMortars", []];
			private _staticMortarClass = if (count _staticMortars > 0) then { _staticMortars select 0 } else { "" };
			private _mortarPrice = [_staticMortarClass, 500] call _fnc_resolveNativeVehiclePrice;
			_money = _money + _mortarPrice;
		};

		// Apply Strategic Deployment Multiplier
		_money = round (_money * _deployMultiplier);

		// Emergency fallback if calculated cost is zero/invalid
		if (_money <= 0) then {
			_money = round ((_hr * 20) * _deployMultiplier);
		};
	} else {
		if (_squadIndex == 14) then {
			// --- GARAGE CREW — crew is auto-generated by createVehicleCrew at spawn time.
			// No HR deducted (no infantry recruited). Flat deployment fee covers operational overhead.
			_hr = 0;
			private _deployFee = 150; // Fixed logistics/ops fee for deploying a garage vehicle
			_money = round (_deployFee * _deployMultiplier);
			if (_money <= 0) then { _money = 150; };
		} else {
			// --- VEHICLE SQUADS ---
			_hr = 2; // 2 crew members
			private _totalCrewCost = 2 * _crewUnitCost;

			private _emergencyFallbackPrice = switch (_squadIndex) do {
				case 6: { 300 };   // Armed Technical
				case 7: { 400 };   // AT Technical
				case 9: { 1000 };  // Anti-Air Vehicle
				case 11: { 1500 }; // Armored APC / IFV
				case 12: { 3000 }; // Combat Tank
				default { 500 };
			};

			private _vehBasePrice = [_vehType, _emergencyFallbackPrice] call _fnc_resolveNativeVehiclePrice;
			private _baseVehicleSquadCost = _totalCrewCost + _vehBasePrice;

			// Apply Strategic Deployment Multiplier
			_money = round (_baseVehicleSquadCost * _deployMultiplier);
			if (_money <= 0) then { _money = round ((_totalCrewCost + _emergencyFallbackPrice) * _deployMultiplier); };
		};
	};

	[_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName]
};

A3A_fnc_planning_updateGarageVehicleDetails = {
	params ["_display"];
	private _cardList = _display displayCtrl 8520;
	private _detailsPanel = _display displayCtrl 8530;
	private _btnConfirm = _display displayCtrl 8540;
	private _btnSelect = _display displayCtrl 8541;
	private _btnHeaderSelect = _display displayCtrl 8542;

	if (isNull _cardList || isNull _detailsPanel) exitWith {};

	private _selIdx = lbCurSel _cardList;
	if (_selIdx == -1) exitWith {
		_detailsPanel ctrlSetStructuredText parseText "<t align='center' color='#888888'><br/><br/><br/>No vehicle selected.<br/>Choose a vehicle from the list on the left.</t>";
		{
			if (!isNull _x) then {
				_x ctrlEnable false;
				_x ctrlSetTooltip "Highlight an available vehicle from the list to select it.";
			};
		} forEach [_btnConfirm, _btnSelect, _btnHeaderSelect];
	};

	private _dataList = _cardList getVariable ["vehiclesData", []];
	if (_selIdx < 0 || { _selIdx >= count _dataList }) exitWith {
		_detailsPanel ctrlSetStructuredText parseText "<t align='center' color='#888888'><br/><br/><br/>No vehicle selected.</t>";
		{
			if (!isNull _x) then {
				_x ctrlEnable false;
				_x ctrlSetTooltip "Highlight an available vehicle from the list to select it.";
			};
		} forEach [_btnConfirm, _btnSelect, _btnHeaderSelect];
	};

	private _item = _dataList select _selIdx;
	_item params ["_dispName", "_class", "_crewCount", "_vehUID", "_category", "_subcat", "_isAvailable", "_reason", "_healthPct", "_fuelPct", "_ammoPct", "_condition", "_weaponsList", "_picture", "_availableCount"];

	{
		if (!isNull _x) then {
			_x ctrlEnable _isAvailable;
			if (_isAvailable) then {
				_x ctrlSetTooltip format ["Confirm selection of %1 and return to Attack Planning menu.", _dispName];
			} else {
				_x ctrlSetTooltip format ["Unavailable: %1", _reason];
			};
		};
	} forEach [_btnConfirm, _btnSelect, _btnHeaderSelect];

	private _statusColor = switch (_condition) do {
		case "Operational": { "#84B062" };
		case "Damaged": { "#E3DCBE" };
		default { "#FF5555" };
	};

	private _availText = if (_isAvailable) then {
		"<t color='#84B062'>Ready for Deployment</t>"
	} else {
		format ["<t color='#FF5555'>UNAVAILABLE (%1)</t>", _reason]
	};

	private _imgHtml = "";
	if (_picture != "") then {
		_imgHtml = format ["<img image='%1' size='4.5' align='center'/><br/>", _picture];
	};

	private _html = format [
		"%1<t size='1.25' font='PuristaBold' color='#E3DCBE'>%2</t><br/>" +
		"<t size='0.85' color='#888888'>%3</t><br/><br/>" +
		"<t color='#FFFFFF'>Category:</t> <t color='#84B062'>%4 (%5)</t><br/>" +
		"<t color='#FFFFFF'>Crew Required:</t> <t color='#E3DCBE'>%6 Members</t><br/>" +
		"<t color='#FFFFFF'>Available Copies:</t> <t color='#84B062'>%7</t><br/><br/>" +
		"<t color='#FFFFFF'>Condition:</t> <t color='%8'>%9</t><br/>" +
		"<t color='#FFFFFF'>Health:</t> <t color='%8'>%10%%</t> | <t color='#FFFFFF'>Fuel:</t> %11%%<br/>" +
		"<t color='#FFFFFF'>Status:</t> %12<br/><br/>" +
		"<t size='1.0' font='PuristaMedium' color='#E3DCBE'>MOUNTED WEAPONS:</t><br/>" +
		"<t size='0.85' color='#DDDDDD'>%13</t>",
		_imgHtml,
		_dispName,
		_class,
		_category,
		_subcat,
		_crewCount,
		_availableCount,
		_statusColor,
		_condition,
		_healthPct,
		_fuelPct,
		_availText,
		_weaponsList
	];

	_detailsPanel ctrlSetStructuredText parseText _html;
	_detailsPanel ctrlCommit 0;
};

A3A_fnc_planning_refreshGarageBrowserList = {
	params ["_display"];
	private _modalGroup = _display displayCtrl 8500;
	if (isNull _modalGroup) exitWith {};

	private _cardList = _display displayCtrl 8520;
	lbClear _cardList;

	private _search = toLower (missionNamespace getVariable ["A3A_planning_garageSearchFilter", ""]);
	private _catFilter = missionNamespace getVariable ["A3A_planning_garageCatFilter", "ALL"];
	private _sortIdx = missionNamespace getVariable ["A3A_planning_garageSortIdx", 0];

	private _allVehicles = call A3A_fnc_planning_getAvailableGarageVehicles;

	// Filter by search term & category filter
	private _filtered = _allVehicles select {
		_x params ["_dispName", "_class", "_crewCount", "_vehUID", "_category", "_subcat", "_isAvailable", "_reason"];
		private _passSearch = (_search == "" || { (toLower _dispName find _search) != -1 } || { (toLower _class find _search) != -1 } || { (toLower _subcat find _search) != -1 });
		private _passCat = (_catFilter == "ALL" || { _category == _catFilter });
		_passSearch && _passCat
	};

	// Sort filtered list
	switch (_sortIdx) do {
		case 0: { _filtered = [_filtered, [], { _x select 0 }, "ASCEND"] call BIS_fnc_sortBy; }; // Name
		case 1: { _filtered = [_filtered, [], { _x select 4 }, "ASCEND"] call BIS_fnc_sortBy; }; // Category
		case 2: { _filtered = [_filtered, [], { _x select 8 }, "DESCEND"] call BIS_fnc_sortBy; }; // Health
		case 3: { _filtered = [_filtered, [], { _x select 9 }, "DESCEND"] call BIS_fnc_sortBy; }; // Fuel
		case 4: { _filtered = [_filtered, [], { if (_x select 6) then { 1 } else { 0 } }, "DESCEND"] call BIS_fnc_sortBy; }; // Availability
	};

	_cardList setVariable ["vehiclesData", _filtered];

	{
		_x params ["_dispName", "_class", "_crewCount", "_vehUID", "_category", "_subcat", "_isAvailable", "_reason", "_healthPct", "_fuelPct", "_ammoPct", "_condition", "_weaponsList", "_picture", "_availableCount"];

		private _cardText = "";
		if (_isAvailable) then {
			_cardText = format ["[%1] %2 — %3 | Health: %4%% | Fuel: %5%% | Copies: %6", _category, _dispName, _subcat, _healthPct, _fuelPct, _availableCount];
		} else {
			_cardText = format ["[%1] %2 — [%3]", _category, _dispName, _reason];
		};

		private _idx = _cardList lbAdd _cardText;
		if (_isAvailable) then {
			_cardList lbSetData [_idx, _class];
			private _color = switch (_condition) do {
				case "Operational": { [0.5, 0.85, 0.5, 1] };
				case "Damaged": { [0.9, 0.85, 0.4, 1] };
				default { [0.9, 0.4, 0.4, 1] };
			};
			_cardList lbSetColor [_idx, _color];
		} else {
			_cardList lbSetData [_idx, "DISABLED|" + _reason];
			_cardList lbSetColor [_idx, [0.6, 0.6, 0.6, 1]];
		};
	} forEach _filtered;

	if (lbSize _cardList > 0) then {
		_cardList lbSetCurSel 0;
	};
	[_display] call A3A_fnc_planning_updateGarageVehicleDetails;
};

A3A_fnc_planning_closeGarageBrowser = {
	params ["_display"];
	if (!isNull _display) then {
		private _modal = _display displayCtrl 8500;
		if (!isNull _modal) then { ctrlDelete _modal; };
		private _blocker = _display displayCtrl 8499;
		if (!isNull _blocker) then { ctrlDelete _blocker; };
	};
	if (!isNil "A3A_planning_garageEscEH" && { !isNull _display }) then {
		_display displayRemoveEventHandler ["KeyDown", A3A_planning_garageEscEH];
		A3A_planning_garageEscEH = nil;
	};
	if (!isNil "A3A_planning_garageBlur") then {
		A3A_planning_garageBlur ppeffectEnable false;
		ppEffectDestroy A3A_planning_garageBlur;
		A3A_planning_garageBlur = nil;
	};
};

A3A_fnc_planning_autoQueueGarageVehicle = {
	params ["_display", "_selectedGarageClass"];

	if (_selectedGarageClass == "") exitWith {
		[_display] call A3A_fnc_planning_ui;
	};

	A3A_planning_selectedSquadIndex = 14;

	private _entryCombo = _display displayCtrl 8022;
	private _entry = "";
	if (!isNull _entryCombo && { lbCurSel _entryCombo != -1 }) then {
		_entry = _entryCombo lbData (lbCurSel _entryCombo);
	};
	if (_entry == "" && { count A3A_planning_entryPoints > 0 }) then {
		_entry = A3A_planning_entryPoints select 0;
	};

	if (_entry == "") exitWith {
		["Vehicle Selected", "Vehicle selected. Create or select a staging area to queue this vehicle.", false] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	};

	private _maxSiegeSquads = missionNamespace getVariable ["A3A_tweak_maxSiegeSquads", 10];
	if (count A3A_planning_queue >= _maxSiegeSquads) exitWith {
		["Limit Reached", format ["You cannot queue more than %1 squads for a single siege.", _maxSiegeSquads], true] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	};

	private _availVehs = call A3A_fnc_planning_getAvailableGarageVehicles;
	private _matchingVeh = _availVehs select { (_x select 1) == _selectedGarageClass && (_x select 6) };
	if (count _matchingVeh == 0) exitWith {
		["Denied", "Selected vehicle is no longer available in the HQ Garage.", true] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	};

	private _reserved = missionNamespace getVariable ["A3A_planning_reservedGarageVehicles", []];
	private _reservedCount = { _x == _selectedGarageClass } count _reserved;
	private _totalAvail = (_matchingVeh select 0) select 14;
	if (_reservedCount >= _totalAvail) exitWith {
		["Denied", "All available copies of this vehicle are already queued.", true] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	};

	private _infra = call A3A_fnc_planning_getFriendlyInfrastructure;
	_infra params ["_hasHelipad", "_hasAirfield"];
	if (_selectedGarageClass isKindOf "Helicopter" && !_hasHelipad) exitWith {
		["Denied", "Selected helicopter requires a friendly helipad or base location.", true] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	};
	if (_selectedGarageClass isKindOf "Plane" && !_hasAirfield) exitWith {
		["Denied", "Selected aircraft requires a friendly airfield.", true] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	};

	private _details = [14, _selectedGarageClass] call A3A_fnc_planning_getSquadDetails;
	_details params ["_squadType", "_idFormat", "_special", "_money", "_hr", "_vehType", "_displayName"];

	if (isNil "A3A_planning_reservedGarageVehicles") then {
		A3A_planning_reservedGarageVehicles = [];
	};
	A3A_planning_reservedGarageVehicles pushBack _vehType;
	missionNamespace setVariable ["A3A_planning_selectedGarageVehicleClass", ""];

	A3A_planning_queue pushBack [_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName, _entry];

	private _cfg = configFile >> "CfgVehicles" >> _vehType;
	private _disp = if (isClass _cfg) then { getText (_cfg >> "displayName") } else { _vehType };
	["Squad Queued", format ["Queued Vehicle Crew: %1", _disp], false] call A3A_fnc_planning_showNotification;

	[_display] call A3A_fnc_planning_ui;
};

A3A_fnc_planning_openGarageBrowser = {
	params ["_display"];

	private _vehicles = call A3A_fnc_planning_getAvailableGarageVehicles;
	if (count _vehicles == 0) exitWith {
		["HQ Garage", "No combat-ready vehicles currently available in the HQ Garage.", true] call A3A_fnc_planning_showNotification;
	};

	// Apply dynamic background blur effect
	if (isNil "A3A_planning_garageBlur") then {
		A3A_planning_garageBlur = ppeffectCreate ["DynamicBlur", 401];
	};
	A3A_planning_garageBlur ppeffectEnable true;
	A3A_planning_garageBlur ppeffectAdjust [2.5];
	A3A_planning_garageBlur ppeffectCommit 0.2;

	private _uW = pixelGridNoUIScale * pixelW;
	private _uH = pixelGridNoUIScale * pixelH;
	private _colorMain = [
		profilenamespace getVariable ["GUI_BCG_RGB_R", 0.376],
		profilenamespace getVariable ["GUI_BCG_RGB_G", 0.125],
		profilenamespace getVariable ["GUI_BCG_RGB_B", 0.043],
		1
	];

	// Clean up any existing modal container & blocker
	[_display] call A3A_fnc_planning_closeGarageBrowser;

	// Full-screen modal background blocker: absorbs mouse clicks behind the browser
	private _modalBlocker = _display ctrlCreate ["TextBase", 8499];
	_modalBlocker ctrlSetPosition [safeZoneX, safeZoneY, safeZoneW, safeZoneH];
	_modalBlocker ctrlSetBackgroundColor [0, 0, 0, 0.45];
	_modalBlocker ctrlEnable true;
	_modalBlocker ctrlSetFade 0;
	_modalBlocker ctrlCommit 0;

	// Consume mouse events to prevent dialog focus loss or unresponsiveness
	_modalBlocker ctrlAddEventHandler ["MouseButtonDown", { true }];
	_modalBlocker ctrlAddEventHandler ["MouseButtonUp", { true }];

	// Create Modal Controls Group (Overlay on right side / center)
	private _modalGroup = _display ctrlCreate ["ScrtRscControlsGroup", 8500];
	_modalGroup ctrlSetPosition [safeZoneX + 0.28 * safeZoneW, safeZoneY + 6 * _uH, 70 * _uW, 48 * _uH];
	_modalGroup ctrlSetFade 0;
	_modalGroup ctrlCommit 0;

	// Keyboard event handler: ESC to cancel, ENTER to confirm selected vehicle
	A3A_planning_garageEscEH = _display displayAddEventHandler ["KeyDown", {
		params ["_display", "_key"];
		if (_key == 1) exitWith { // ESC key
			[_display] call A3A_fnc_planning_closeGarageBrowser;
			true // Consume event
		};
		if (_key in [28, 156]) exitWith { // ENTER / Numpad ENTER key
			private _list = _display displayCtrl 8520;
			if (!isNull _list && { lbCurSel _list != -1 }) then {
				private _class = _list lbData (lbCurSel _list);
				if (_class != "" && { (_class find "DISABLED") != 0 }) then {
					missionNamespace setVariable ["A3A_planning_selectedGarageVehicleClass", _class];
					[_display] call A3A_fnc_planning_closeGarageBrowser;
					[_display, _class] call A3A_fnc_planning_autoQueueGarageVehicle;
				};
			};
			true // Consume event
		};
		false
	}];
	A3A_planning_garageEscEH = _escEH;

	// Dark semi-transparent background
	private _bg = _display ctrlCreate ["TextBase", 8501, _modalGroup];
	_bg ctrlSetPosition [0, 0, 70 * _uW, 48 * _uH];
	_bg ctrlSetBackgroundColor [0.06, 0.06, 0.06, 0.96];
	_bg ctrlSetFade 0;
	_bg ctrlCommit 0;

	// Title
	private _title = _display ctrlCreate ["TextBase", 8502, _modalGroup];
	_title ctrlSetPosition [1 * _uW, 1 * _uH, 45 * _uW, 2 * _uH];
	_title ctrlSetText "HQ GARAGE — VEHICLE BROWSER";
	_title ctrlSetFont "PuristaBold";
	_title ctrlSetFade 0;
	_title ctrlCommit 0;

	// Select Vehicle Header Button (directly beside CANCEL button)
	private _btnHeaderSelect = _display ctrlCreate ["ButtonBase", 8542, _modalGroup];
	_btnHeaderSelect ctrlSetPosition [50 * _uW, 1 * _uH, 12 * _uW, 2 * _uH];
	_btnHeaderSelect ctrlSetText "SELECT VEHICLE";
	_btnHeaderSelect ctrlSetBackgroundColor _colorMain;
	_btnHeaderSelect ctrlSetFade 0;
	_btnHeaderSelect ctrlCommit 0;

	// Cancel / Close Button
	private _btnClose = _display ctrlCreate ["ButtonBase", 8503, _modalGroup];
	_btnClose ctrlSetPosition [63 * _uW, 1 * _uH, 6 * _uW, 2 * _uH];
	_btnClose ctrlSetText "CANCEL";
	_btnClose ctrlSetBackgroundColor [0.6, 0.1, 0.1, 1];
	_btnClose ctrlSetFade 0;
	_btnClose ctrlCommit 0;
	_btnClose ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		[_display] call A3A_fnc_planning_closeGarageBrowser;
	}];

	// Search Edit
	private _searchLabel = _display ctrlCreate ["TextBase", 8504, _modalGroup];
	_searchLabel ctrlSetPosition [1 * _uW, 3.8 * _uH, 7 * _uW, 1.8 * _uH];
	_searchLabel ctrlSetText "Search:";
	_searchLabel ctrlSetFont "PuristaLight";
	_searchLabel ctrlCommit 0;

	private _searchEdit = _display ctrlCreate ["RscEdit", 8505, _modalGroup];
	_searchEdit ctrlSetPosition [8 * _uW, 3.6 * _uH, 25 * _uW, 2 * _uH];
	_searchEdit ctrlSetBackgroundColor [0.15, 0.15, 0.15, 1];
	_searchEdit ctrlSetTextColor [1, 1, 1, 1];
	_searchEdit ctrlSetText (missionNamespace getVariable ["A3A_planning_garageSearchFilter", ""]);
	_searchEdit ctrlCommit 0;

	// Sort Combo
	private _sortLabel = _display ctrlCreate ["TextBase", 8506, _modalGroup];
	_sortLabel ctrlSetPosition [35 * _uW, 3.8 * _uH, 5 * _uW, 1.8 * _uH];
	_sortLabel ctrlSetText "Sort:";
	_sortLabel ctrlSetFont "PuristaLight";
	_sortLabel ctrlCommit 0;

	private _sortCombo = _display ctrlCreate ["BaseComboBox", 8507, _modalGroup];
	_sortCombo ctrlSetPosition [40 * _uW, 3.6 * _uH, 28 * _uW, 2 * _uH];
	_sortCombo ctrlSetBackgroundColor [0.15, 0.15, 0.15, 1];
	_sortCombo ctrlSetTextColor [1, 1, 1, 1];
	{ _sortCombo lbAdd _x; } forEach ["Name", "Category", "Health (Highest)", "Fuel (Highest)", "Availability"];
	_sortCombo lbSetCurSel (missionNamespace getVariable ["A3A_planning_garageSortIdx", 0]);
	_sortCombo ctrlCommit 0;

	// Category Buttons
	private _categories = [
		["ALL", "All Assets"],
		["CARS", "Cars / Techs"],
		["ARMOR", "Armor / Tanks"],
		["HELICOPTERS", "Helicopters"],
		["AIRCRAFT", "Aircraft"],
		["ARTILLERY", "Artillery"],
		["NAVAL", "Naval"]
	];

	private _currentCat = missionNamespace getVariable ["A3A_planning_garageCatFilter", "ALL"];

	{
		_x params ["_catKey", "_catLabel"];
		private _btnX = 1 + (_forEachIndex * 9.6);
		private _catBtn = _display ctrlCreate ["ButtonBase", 8510 + _forEachIndex, _modalGroup];
		_catBtn ctrlSetPosition [_btnX * _uW, 6.2 * _uH, 9.3 * _uW, 2 * _uH];
		_catBtn ctrlSetText _catLabel;
		if (_catKey == _currentCat) then {
			_catBtn ctrlSetBackgroundColor _colorMain;
		} else {
			_catBtn ctrlSetBackgroundColor [0.2, 0.2, 0.2, 0.9];
		};
		_catBtn ctrlCommit 0;
		_catBtn ctrlAddEventHandler ["ButtonClick", {
			private _btn = _this select 0;
			private _idc = ctrlIDC _btn;
			private _idx = _idc - 8510;
			private _catKeys = ["ALL", "CARS", "ARMOR", "HELICOPTERS", "AIRCRAFT", "ARTILLERY", "NAVAL"];
			private _catKey = if (_idx >= 0 && { _idx < count _catKeys }) then { _catKeys select _idx } else { "ALL" };

			missionNamespace setVariable ["A3A_planning_garageCatFilter", _catKey];
			private _display = ctrlParent _btn;

			private _mGroup = _display displayCtrl 8500;
			if (!isNull _mGroup) then {
				{
					private _b = _mGroup displayCtrl (8510 + _forEachIndex);
					if (!isNull _b) then {
						if (_x == _catKey) then {
							_b ctrlSetBackgroundColor [
								profilenamespace getVariable ["GUI_BCG_RGB_R", 0.376],
								profilenamespace getVariable ["GUI_BCG_RGB_G", 0.125],
								profilenamespace getVariable ["GUI_BCG_RGB_B", 0.043],
								1
							];
						} else {
							_b ctrlSetBackgroundColor [0.2, 0.2, 0.2, 0.9];
						};
					};
				} forEach ["ALL", "CARS", "ARMOR", "HELICOPTERS", "AIRCRAFT", "ARTILLERY", "NAVAL"];
			};

			[_display] call A3A_fnc_planning_refreshGarageBrowserList;
		}];
	} forEach _categories;

	// Vehicle Cards List Box
	private _cardList = _display ctrlCreate ["RscListBox", 8520, _modalGroup];
	_cardList ctrlSetPosition [1 * _uW, 8.8 * _uH, 40 * _uW, 34.5 * _uH];
	_cardList ctrlSetBackgroundColor [0.1, 0.1, 0.1, 0.8];
	_cardList ctrlSetTextColor [1, 1, 1, 1];
	_cardList ctrlSetFont "PuristaLight";
	_cardList ctrlCommit 0;

	// Vehicle Details Panel
	private _detailsPanel = _display ctrlCreate ["RscStructuredText", 8530, _modalGroup];
	_detailsPanel ctrlSetPosition [42 * _uW, 8.8 * _uH, 27 * _uW, 34.5 * _uH];
	_detailsPanel ctrlSetBackgroundColor [0.12, 0.12, 0.12, 0.9];
	_detailsPanel ctrlCommit 0;

	// Select Vehicle Button (directly below vehicle list on left)
	private _btnSelect = _display ctrlCreate ["ButtonBase", 8541, _modalGroup];
	_btnSelect ctrlSetPosition [1 * _uW, 44 * _uH, 40 * _uW, 3 * _uH];
	_btnSelect ctrlSetText "SELECT VEHICLE";
	_btnSelect ctrlSetBackgroundColor _colorMain;
	_btnSelect ctrlCommit 0;

	// Confirm Selection Button (lower-right corner under details panel)
	private _btnConfirm = _display ctrlCreate ["ButtonBase", 8540, _modalGroup];
	_btnConfirm ctrlSetPosition [42 * _uW, 44 * _uH, 27 * _uW, 3 * _uH];
	_btnConfirm ctrlSetText "CONFIRM SELECTION";
	_btnConfirm ctrlSetBackgroundColor _colorMain;
	_btnConfirm ctrlCommit 0;

	_searchEdit ctrlAddEventHandler ["KeyUp", {
		private _edit = _this select 0;
		missionNamespace setVariable ["A3A_planning_garageSearchFilter", ctrlText _edit];
		private _display = ctrlParent _edit;
		[_display] call A3A_fnc_planning_refreshGarageBrowserList;
	}];

	_sortCombo ctrlAddEventHandler ["LBSelChanged", {
		private _combo = _this select 0;
		missionNamespace setVariable ["A3A_planning_garageSortIdx", lbCurSel _combo];
		private _display = ctrlParent _combo;
		[_display] call A3A_fnc_planning_refreshGarageBrowserList;
	}];

	_cardList ctrlAddEventHandler ["LBSelChanged", {
		private _list = _this select 0;
		private _display = ctrlParent _list;
		[_display] call A3A_fnc_planning_updateGarageVehicleDetails;
	}];

	// Double-click shortcut: immediately select vehicle & close browser
	_cardList ctrlAddEventHandler ["LBDblClick", {
		private _list = _this select 0;
		private _display = ctrlParent _list;
		private _selIdx = lbCurSel _list;
		if (_selIdx != -1) then {
			private _class = _list lbData _selIdx;
			if (_class != "" && { (_class find "DISABLED") != 0 }) then {
				missionNamespace setVariable ["A3A_planning_selectedGarageVehicleClass", _class];
				[_display] call A3A_fnc_planning_closeGarageBrowser;
				[_display, _class] call A3A_fnc_planning_autoQueueGarageVehicle;
			} else {
				if ((_class find "DISABLED|") == 0) then {
					private _reason = (_class splitString "|") select 1;
					["Denied", _reason, true] call A3A_fnc_planning_showNotification;
				};
			};
		};
	}];

	private _fnc_onConfirmSelect = {
		private _btn = _this select 0;
		private _display = ctrlParent _btn;
		private _list = _display displayCtrl 8520;
		private _selIdx = lbCurSel _list;
		if (_selIdx != -1) then {
			private _class = _list lbData _selIdx;
			if (_class == "" || { (_class find "DISABLED") == 0 }) exitWith {
				private _reason = "Selected vehicle is unavailable for deployment.";
				if ((_class find "DISABLED|") == 0) then {
					_reason = (_class splitString "|") select 1;
				};
				["Denied", _reason, true] call A3A_fnc_planning_showNotification;
			};
			missionNamespace setVariable ["A3A_planning_selectedGarageVehicleClass", _class];
			[_display] call A3A_fnc_planning_closeGarageBrowser;
			[_display, _class] call A3A_fnc_planning_autoQueueGarageVehicle;
		} else {
			["Denied", "Please select a vehicle from the list first.", true] call A3A_fnc_planning_showNotification;
		};
	};

	_btnHeaderSelect ctrlAddEventHandler ["ButtonClick", _fnc_onConfirmSelect];
	_btnSelect ctrlAddEventHandler ["ButtonClick", _fnc_onConfirmSelect];
	_btnConfirm ctrlAddEventHandler ["ButtonClick", _fnc_onConfirmSelect];

	[_display] call A3A_fnc_planning_refreshGarageBrowserList;
};

private _controlsGroup = _display displayCtrl 8000;
if (isNull _controlsGroup) then {
	_controlsGroup = _display ctrlCreate ["ScrtRscControlsGroup", 8000];
	_controlsGroup ctrlSetPosition [-0.4 * safeZoneW + safeZoneX, safeZoneY + 12 * _uH, 26 * _uW, safeZoneH - 14 * _uH];
	_controlsGroup ctrlSetFade 0;
	_controlsGroup ctrlCommit 0;
};

private _ctrlTitleCheck = _display displayCtrl 8010;
if (isNull _ctrlTitleCheck) then {
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

	if (_isReinforceMode) then {
		_ctrlBtnPlanTarget ctrlEnable false;
		_ctrlBtnPlanTarget ctrlSetTooltip "Target is locked to the ongoing siege operation.";
	};

	_ctrlBtnPlanTarget ctrlAddEventHandler ["ButtonClick", {
		if (call A3A_fnc_planning_isSiegeActive) exitWith {
			["Denied", "Target is locked to the ongoing siege operation.", true] call A3A_fnc_planning_showNotification;
		};
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

	private _ctrlObjText = _display ctrlCreate ["RscStructuredText", 8011, _controlsGroup];
	_ctrlObjText ctrlSetPosition [1 * _uW, 4.2 * _uH, 22 * _uW, 1.5 * _uH];
	_ctrlObjText ctrlSetFont "PuristaLight";
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
	// Squad selection ListBox (Multi-row scrollable list - expanded to 11.5 uH for better visibility on 1080p)
	private _ctrlSquadCombo = _display ctrlCreate ["RscListBox", 8020, _controlsGroup];
	_ctrlSquadCombo ctrlSetPosition [1 * _uW, 9 * _uH, 22 * _uW, 11.5 * _uH];
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
	_ctrlSquadEntryCombo ctrlSetPosition [1 * _uW, 21 * _uH, 22 * _uW, 2 * _uH];
	_ctrlSquadEntryCombo ctrlSetBackgroundColor _colorListBg;
	_ctrlSquadEntryCombo ctrlSetTextColor _colorListText;
	_ctrlSquadEntryCombo ctrlSetFont "PuristaLight";
	_ctrlSquadEntryCombo ctrlShow true;
	_ctrlSquadEntryCombo ctrlSetFade 0;
	_ctrlSquadEntryCombo ctrlCommit 0;

	// HQ Garage vehicle browser controls — created here, populated during refresh pass
	private _ctrlVehLabel = _display ctrlCreate ["TextBase", 8031, _controlsGroup];
	_ctrlVehLabel ctrlSetPosition [1 * _uW, 23.5 * _uH, 22 * _uW, 1.5 * _uH];
	_ctrlVehLabel ctrlSetText "HQ Garage Vehicle:";
	_ctrlVehLabel ctrlSetFont "PuristaLight";
	_ctrlVehLabel ctrlShow false;
	_ctrlVehLabel ctrlSetFade 0;
	_ctrlVehLabel ctrlCommit 0;

	private _ctrlBtnVehBrowse = _display ctrlCreate ["ButtonBase", 8030, _controlsGroup];
	_ctrlBtnVehBrowse ctrlSetPosition [1 * _uW, 25 * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnVehBrowse ctrlSetText "Open HQ Garage Browser";
	_ctrlBtnVehBrowse ctrlSetBackgroundColor _colorMain;
	_ctrlBtnVehBrowse ctrlShow false;
	_ctrlBtnVehBrowse ctrlSetFade 0;
	_ctrlBtnVehBrowse ctrlCommit 0;

	_ctrlBtnVehBrowse ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		[_display] call A3A_fnc_planning_openGarageBrowser;
	}];

	private _ctrlVehSummary = _display ctrlCreate ["RscStructuredText", 8032, _controlsGroup];
	_ctrlVehSummary ctrlSetPosition [1 * _uW, 27.2 * _uH, 22 * _uW, 1.8 * _uH];
	_ctrlVehSummary ctrlSetFont "PuristaLight";
	_ctrlVehSummary ctrlShow false;
	_ctrlVehSummary ctrlSetFade 0;
	_ctrlVehSummary ctrlCommit 0;

	// Queue button — positioned below vehicle browser if visible, otherwise directly below staging
	private _isGarageCrew = (A3A_planning_selectedSquadIndex == 14);
	private _queueBtnY = if (_isGarageCrew) then { 29.5 } else { 23.5 };
	private _ctrlBtnQueue = _display ctrlCreate ["ButtonBase", 8023, _controlsGroup];
	_ctrlBtnQueue ctrlSetPosition [1 * _uW, _queueBtnY * _uH, 22 * _uW, 2 * _uH];
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

		// Garage Crew: validate a vehicle is selected & available from HQ Garage Browser
		private _selectedGarageClass = "";
		if (A3A_planning_selectedSquadIndex == 14) then {
			_selectedGarageClass = missionNamespace getVariable ["A3A_planning_selectedGarageVehicleClass", ""];
			if (_selectedGarageClass == "") exitWith {
				["Denied", "Select a vehicle from the HQ Garage first.", true] call A3A_fnc_planning_showNotification;
				[_display] call A3A_fnc_planning_openGarageBrowser;
			};

			private _availVehs = call A3A_fnc_planning_getAvailableGarageVehicles;
			private _matchingVeh = _availVehs select { (_x select 1) == _selectedGarageClass && (_x select 6) };
			if (count _matchingVeh == 0) exitWith {
				["Denied", "Selected vehicle is no longer available in the HQ Garage.", true] call A3A_fnc_planning_showNotification;
			};

			private _reserved = missionNamespace getVariable ["A3A_planning_reservedGarageVehicles", []];
			private _reservedCount = { _x == _selectedGarageClass } count _reserved;
			private _totalAvail = (_matchingVeh select 0) select 14;
			if (_reservedCount >= _totalAvail) exitWith {
				["Denied", "All available copies of this vehicle are already queued.", true] call A3A_fnc_planning_showNotification;
			};

			private _infra = call A3A_fnc_planning_getFriendlyInfrastructure;
			_infra params ["_hasHelipad", "_hasAirfield"];
			if (_selectedGarageClass isKindOf "Helicopter" && !_hasHelipad) exitWith {
				["Denied", "Selected helicopter requires a friendly helipad or base location.", true] call A3A_fnc_planning_showNotification;
			};
			if (_selectedGarageClass isKindOf "Plane" && !_hasAirfield) exitWith {
				["Denied", "Selected aircraft requires a friendly airfield.", true] call A3A_fnc_planning_showNotification;
			};
		};

		if (A3A_planning_selectedSquadIndex == 14 && { _selectedGarageClass == "" }) exitWith {};

		private _details = [A3A_planning_selectedSquadIndex, _selectedGarageClass] call A3A_fnc_planning_getSquadDetails;
		_details params ["_squadType", "_idFormat", "_special", "_money", "_hr", "_vehType", "_displayName"];

		// Reserve the garage vehicle to prevent double-queuing
		if (_special == "GarageCrew" && { _vehType != "" }) then {
			if (isNil "A3A_planning_reservedGarageVehicles") then {
				A3A_planning_reservedGarageVehicles = [];
			};
			A3A_planning_reservedGarageVehicles pushBack _vehType;
			missionNamespace setVariable ["A3A_planning_selectedGarageVehicleClass", ""];
		};

		A3A_planning_queue pushBack [_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName, _entry];
		[_display] call A3A_fnc_planning_ui;
	}];

	    // --- QUEUED list ---
	private _ctrlQueueList = _display ctrlCreate ["RscListBox", 8014, _controlsGroup];
	_ctrlQueueList ctrlSetPosition [1 * _uW, 26 * _uH, 22 * _uW, 6 * _uH];
	_ctrlQueueList ctrlSetBackgroundColor _colorListBg;
	_ctrlQueueList ctrlSetTextColor _colorListText;
	_ctrlQueueList ctrlSetFade 0;
	_ctrlQueueList ctrlCommit 0;

	private _ctrlBtnRemove = _display ctrlCreate ["ButtonBase", 8024, _controlsGroup];
	_ctrlBtnRemove ctrlSetPosition [1 * _uW, 32.5 * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnRemove ctrlSetText "Remove Selected";
	_ctrlBtnRemove ctrlSetBackgroundColor _colorMain;
	_ctrlBtnRemove ctrlSetFade 0;
	_ctrlBtnRemove ctrlCommit 0;
	_ctrlBtnRemove ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		private _list = _display displayCtrl 8014;
		private _selIdx = lbCurSel _list;
		if (_selIdx != -1) then {
			private _entry = A3A_planning_queue select _selIdx;
			// Un-reserve garage vehicle if this was a GarageCrew entry
			if (((_entry select 2) == "GarageCrew") && { (_entry select 5) != "" }) then {
				private _vClass = _entry select 5;
				private _rIdx = A3A_planning_reservedGarageVehicles find _vClass;
				if (_rIdx != -1) then {
					A3A_planning_reservedGarageVehicles deleteAt _rIdx;
				};
			};
			A3A_planning_queue deleteAt _selIdx;
			[_display] call A3A_fnc_planning_ui;
		};
	}];

	    // --- COSTS & COMMENCE ---
	private _ctrlCapChk = _display ctrlCreate ["RscCheckBox", 8042, _controlsGroup];
	_ctrlCapChk ctrlSetPosition [1 * _uW, 35 * _uH, 2 * _uW, 2 * _uH];
	_ctrlCapChk ctrlSetFade 0;
	_ctrlCapChk ctrlCommit 0;
	    _ctrlCapChk cbSetChecked true;

	private _ctrlCapLabel = _display ctrlCreate ["TextBase", 8043, _controlsGroup];
	_ctrlCapLabel ctrlSetPosition [3.5 * _uW, 35 * _uH, 19.5 * _uW, 2 * _uH];
	_ctrlCapLabel ctrlSetText "Automatically Capture Objective";
	_ctrlCapLabel ctrlSetFont "PuristaLight";
	_ctrlCapLabel ctrlSetFade 0;
	_ctrlCapLabel ctrlCommit 0;

	private _ctrlCostLabel = _display ctrlCreate ["RscStructuredText", 8025, _controlsGroup];
	_ctrlCostLabel ctrlSetPosition [1 * _uW, 37.5 * _uH, 22 * _uW, 5.5 * _uH];
	_ctrlCostLabel ctrlSetFont "PuristaLight";
	_ctrlCostLabel ctrlSetFade 0;
	_ctrlCostLabel ctrlCommit 0;

	private _ctrlBtnCommence = _display ctrlCreate ["ButtonBase", 8026, _controlsGroup];
	_ctrlBtnCommence ctrlSetPosition [1 * _uW, 43.5 * _uH, 22 * _uW, 3 * _uH];
	_ctrlBtnCommence ctrlSetText (if (_isReinforceMode) then { "Deploy Reinforcements" } else { "Commence Siege" });
	_ctrlBtnCommence ctrlSetBackgroundColor (if (_isReinforceMode) then { [0.2, 0.5, 0.2, 1] } else { [0.6, 0.1, 0.1, 1] });
	_ctrlBtnCommence ctrlSetFade 0;
	_ctrlBtnCommence ctrlCommit 0;
	_ctrlBtnCommence ctrlSetTooltip (if (_isReinforceMode) then { "Deploy queued reinforcement squads to join the active siege." } else { "Commence the siege operation with queued squads." });

	private _ctrlBtnClear = _display ctrlCreate ["ButtonBase", 8027, _controlsGroup];
	_ctrlBtnClear ctrlSetPosition [1 * _uW, 47 * _uH, 22 * _uW, 2.5 * _uH];
	_ctrlBtnClear ctrlSetText "Clear Plan";
	_ctrlBtnClear ctrlSetBackgroundColor [0.35, 0.35, 0.35, 1];
	_ctrlBtnClear ctrlSetFade 0;
	_ctrlBtnClear ctrlCommit 0;
	_ctrlBtnClear ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		[true] call A3A_fnc_planning_localCleanupMarkers;
		// Clear all garage vehicle reservations
		A3A_planning_reservedGarageVehicles = [];
		["Plan Cleared", "The current siege plan and map markers have been cleared.", false] call A3A_fnc_planning_showNotification;
		[_display] call A3A_fnc_planning_ui;
	}];
	_ctrlBtnCommence ctrlAddEventHandler ["ButtonClick", {
		private _display = ctrlParent (_this select 0);
		private _isReinforcement = call A3A_fnc_planning_isSiegeActive;

		if (A3A_planning_objective == "") exitWith {
			["Denied", "You must select a target objective first.", true] call A3A_fnc_planning_showNotification;
		};
		if (count A3A_planning_queue == 0) exitWith {
			["Denied", "You must queue at least one squad to deploy.", true] call A3A_fnc_planning_showNotification;
		};

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

		A3A_planning_queue = [];
		// Garage vehicle reservations are now committed — clear the local reservation list
		A3A_planning_reservedGarageVehicles = [];

		if (_isReinforcement) then {
			["Reinforcements Dispatched", "Reinforcement wave departed HQ to support the ongoing siege!", false] call A3A_fnc_planning_showNotification;
			["REINFORCE", [_totalMoney, _totalHR, clientOwner, _addHC, _queueCopy, _autoCapture, _entryPositions, A3A_planning_objective]] remoteExec ["A3A_fnc_planning_execute", 2];
		} else {
			["Siege Commenced", "All recruited squads have departed HQ. Watch for radio progress transmissions!", false] call A3A_fnc_planning_showNotification;
			["DEPLOY", [_totalMoney, _totalHR, clientOwner, _addHC, _queueCopy, _autoCapture, _entryPositions, A3A_planning_objective]] remoteExec ["A3A_fnc_planning_execute", 2];
		};
	}];

	    // Dummy control for scroll container padding
	private _ctrlDummy = _display ctrlCreate ["TextBase", 8099, _controlsGroup];
	_ctrlDummy ctrlSetPosition [1 * _uW, 51 * _uH, 22 * _uW, 3.5 * _uH];
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
	private _objMarker = A3A_planning_objective;
	private _name = markerText _objMarker;
	if (_name == "") then { _name = markerText ("Dum" + _objMarker); };
	if (_name == "") then { _name = _objMarker; };
	if (_isReinforceMode) then {
		_targetName = format ["<t color='#84B062'>Target (REINFORCING):</t> <t color='#FFFFFF'>%1</t>", _name];
	} else {
		_targetName = format ["<t color='#E3DCBE'>Target:</t> <t color='#FFFFFF'>%1</t>", _name];
	};
} else {
	_targetName = "<t color='#888888'>Target: None Selected</t>";
};
if (!isNull _ctrlObjText) then {
	_ctrlObjText ctrlSetStructuredText parseText _targetName;
	_ctrlObjText ctrlCommit 0;
};

private _ctrlBtnPlanTarget = _display displayCtrl 8015;
if (!isNull _ctrlBtnPlanTarget) then {
	if (_isReinforceMode) then {
		_ctrlBtnPlanTarget ctrlEnable false;
		_ctrlBtnPlanTarget ctrlSetTooltip "Target is locked to the ongoing siege operation.";
	} else {
		_ctrlBtnPlanTarget ctrlEnable true;
		_ctrlBtnPlanTarget ctrlSetTooltip "Click to select a target objective on the map.";
	};
};

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

// Show/hide and populate garage vehicle browser controls based on selection
private _isGarageCrewSelected = (A3A_planning_selectedSquadIndex == 14);
private _ctrlVehLabel = _display displayCtrl 8031;
private _ctrlBtnVehBrowse = _display displayCtrl 8030;
private _ctrlVehSummary = _display displayCtrl 8032;

if (!isNull _ctrlVehLabel && !isNull _ctrlBtnVehBrowse) then {
	_ctrlVehLabel ctrlShow _isGarageCrewSelected;
	_ctrlBtnVehBrowse ctrlShow _isGarageCrewSelected;
	if (!isNull _ctrlVehSummary) then { _ctrlVehSummary ctrlShow _isGarageCrewSelected; };

	if (_isGarageCrewSelected) then {
		private _selClass = missionNamespace getVariable ["A3A_planning_selectedGarageVehicleClass", ""];
		if (_selClass == "") then {
			_ctrlBtnVehBrowse ctrlSetText "Select Vehicle";
			_ctrlVehSummary ctrlSetStructuredText parseText "<t color='#AAAAAA'>Selected Vehicle: None</t>";
		} else {
			_ctrlBtnVehBrowse ctrlSetText "Change Vehicle";
			private _cfg = configFile >> "CfgVehicles" >> _selClass;
			private _disp = if (isClass _cfg) then { getText (_cfg >> "displayName") } else { _selClass };
			private _crew = [_selClass] call A3A_fnc_planning_getVehicleCombatSeatCount;
			_ctrlVehSummary ctrlSetStructuredText parseText format ["<t color='#84B062'>Selected Vehicle:</t> <t color='#FFFFFF'>%1</t> <t color='#E3DCBE'>(Crew: %2)</t>", _disp, _crew];
		};
	};
};

// Layout offset: when garage vehicle browser controls are visible, offset controls by 6uH
private _crewOffset = if (_isGarageCrewSelected) then { 6 } else { 0 };

private _ctrlBtnQueue = _display displayCtrl 8023;
if (!isNull _ctrlBtnQueue) then {
	_ctrlBtnQueue ctrlSetPosition [1 * _uW, (23.5 + _crewOffset) * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnQueue ctrlCommit 0;
};

private _ctrlQueueList = _display displayCtrl 8014;
if (!isNull _ctrlQueueList) then {
	_ctrlQueueList ctrlSetPosition [1 * _uW, (26 + _crewOffset) * _uH, 22 * _uW, 6 * _uH];
	_ctrlQueueList ctrlCommit 0;
};

private _ctrlBtnRemove = _display displayCtrl 8024;
if (!isNull _ctrlBtnRemove) then {
	_ctrlBtnRemove ctrlSetPosition [1 * _uW, (32.5 + _crewOffset) * _uH, 22 * _uW, 2 * _uH];
	_ctrlBtnRemove ctrlCommit 0;
};

private _ctrlCapChk = _display displayCtrl 8042;
if (!isNull _ctrlCapChk) then {
	_ctrlCapChk ctrlSetPosition [1 * _uW, (35 + _crewOffset) * _uH, 2 * _uW, 2 * _uH];
	_ctrlCapChk ctrlCommit 0;
};

private _ctrlCapLabel = _display displayCtrl 8043;
if (!isNull _ctrlCapLabel) then {
	_ctrlCapLabel ctrlSetPosition [3.5 * _uW, (35 + _crewOffset) * _uH, 19.5 * _uW, 2 * _uH];
	_ctrlCapLabel ctrlCommit 0;
};

private _ctrlCostLabel = _display displayCtrl 8025;
if (!isNull _ctrlCostLabel) then {
	_ctrlCostLabel ctrlSetPosition [1 * _uW, (37.5 + _crewOffset) * _uH, 22 * _uW, 5.5 * _uH];
	_ctrlCostLabel ctrlCommit 0;
};

private _ctrlBtnCommence = _display displayCtrl 8026;
if (!isNull _ctrlBtnCommence) then {
	_ctrlBtnCommence ctrlSetPosition [1 * _uW, (43.5 + _crewOffset) * _uH, 22 * _uW, 3 * _uH];
	_ctrlBtnCommence ctrlCommit 0;
};

private _ctrlBtnClear = _display displayCtrl 8027;
if (!isNull _ctrlBtnClear) then {
	_ctrlBtnClear ctrlSetPosition [1 * _uW, (47 + _crewOffset) * _uH, 22 * _uW, 2.5 * _uH];
	_ctrlBtnClear ctrlCommit 0;
};

private _ctrlDummy = _display displayCtrl 8099;
if (!isNull _ctrlDummy) then {
	_ctrlDummy ctrlSetPosition [1 * _uW, (51 + _crewOffset) * _uH, 22 * _uW, 3.5 * _uH];
	_ctrlDummy ctrlCommit 0;
};

// Workflow step checks
private _hasObjective = (A3A_planning_objective != "");
private _hasStaging = (count A3A_planning_entryPoints > 0);
private _hasQueue = (count A3A_planning_queue > 0);

// step 2 enablement (Add/move/Remove Staging)
private _ctrlBtnEntryAdd = _display displayCtrl 8016;
private _ctrlBtnEntryMove = _display displayCtrl 8017;
private _ctrlBtnEntryDel = _display displayCtrl 8018;

if (!isNull _ctrlBtnEntryAdd) then { _ctrlBtnEntryAdd ctrlEnable _hasObjective; };
if (!isNull _ctrlBtnEntryMove) then { _ctrlBtnEntryMove ctrlEnable _hasObjective; };
if (!isNull _ctrlBtnEntryDel) then { _ctrlBtnEntryDel ctrlEnable (_hasObjective && { _hasStaging }); };

if (!_hasObjective) then {
	if (!isNull _ctrlBtnEntryAdd) then { _ctrlBtnEntryAdd ctrlSetTooltip "You must select a target objective first."; };
	if (!isNull _ctrlBtnEntryMove) then { _ctrlBtnEntryMove ctrlSetTooltip "You must select a target objective first."; };
	if (!isNull _ctrlBtnEntryDel) then { _ctrlBtnEntryDel ctrlSetTooltip "You must select a target objective first."; };
} else {
	if (!isNull _ctrlBtnEntryAdd) then { _ctrlBtnEntryAdd ctrlSetTooltip ""; };
	if (!isNull _ctrlBtnEntryMove) then { _ctrlBtnEntryMove ctrlSetTooltip ""; };
	if (!isNull _ctrlBtnEntryDel) then { _ctrlBtnEntryDel ctrlSetTooltip ""; };
};

// step 3 enablement (Recruit/Squad combo list and entry/veh dropdowns)
private _ctrlSquadCombo = _display displayCtrl 8020;
private _ctrlSquadEntryCombo = _display displayCtrl 8022;
private _ctrlBtnVehBrowse = _display displayCtrl 8030;

if (!isNull _ctrlSquadCombo) then { _ctrlSquadCombo ctrlEnable _hasStaging; };
if (!isNull _ctrlSquadEntryCombo) then { _ctrlSquadEntryCombo ctrlEnable _hasStaging; };
if (!isNull _ctrlBtnVehBrowse) then { _ctrlBtnVehBrowse ctrlEnable _hasStaging; };

if (!_hasStaging) then {
	if (!isNull _ctrlSquadCombo) then { _ctrlSquadCombo ctrlSetTooltip "You must configure at least one staging area first."; };
	if (!isNull _ctrlSquadEntryCombo) then { _ctrlSquadEntryCombo ctrlSetTooltip "You must configure at least one staging area first."; };
} else {
	if (!isNull _ctrlSquadCombo) then { _ctrlSquadCombo ctrlSetTooltip ""; };
	if (!isNull _ctrlSquadEntryCombo) then { _ctrlSquadEntryCombo ctrlSetTooltip ""; };
};

private _ctrlCapChk = _display displayCtrl 8042;
private _ctrlCapLabel = _display displayCtrl 8043;
if (!isNull _ctrlCapChk) then { _ctrlCapChk ctrlEnable _hasStaging; };
if (!isNull _ctrlCapLabel) then { _ctrlCapLabel ctrlEnable _hasStaging; };

// High Command and Queue limit checks
private _maxSiegeSquads = missionNamespace getVariable ["A3A_tweak_maxSiegeSquads", 10];
private _currentHcCount = count (hcAllGroups player);
private _maxHcLimit = if (player call A3A_fnc_isMember) then {
	10
} else {
	6
};

private _queueCount = count A3A_planning_queue;
private _selGarageClass = missionNamespace getVariable ["A3A_planning_selectedGarageVehicleClass", ""];
private _garageValid = (!_isGarageCrewSelected || { _selGarageClass != "" });
private _canQueue = (_queueCount < _maxSiegeSquads) && (_currentHcCount + _queueCount < _maxHcLimit) && _hasStaging;
private _canQueueFinal = _canQueue && _garageValid;

if (!isNull _ctrlBtnQueue) then {
	_ctrlBtnQueue ctrlEnable _canQueueFinal;
	if (!_canQueueFinal) then {
		private _tooltip = "";
		if (!_hasStaging) then {
			_tooltip = "You must configure at least one staging area first.";
		} else {
			if (_isGarageCrewSelected && { _selGarageClass == "" }) then {
				_tooltip = "Select a vehicle from the HQ Garage first.";
			} else {
				if (_queueCount >= _maxSiegeSquads) then {
					_tooltip = format ["Deployment limit reached: Maximum of %1 squads per siege.", _maxSiegeSquads];
				} else {
					_tooltip = "High Command limit reached: Cannot recruit more squads.";
				};
			};
		};
		_ctrlBtnQueue ctrlSetTooltip _tooltip;
	} else {
		_ctrlBtnQueue ctrlSetTooltip "";
	};
};

// step 4 enablement (Commence Siege)
private _ctrlBtnCommence = _display displayCtrl 8026;
private _canCommence = _hasObjective && _hasStaging && _hasQueue;

if (!isNull _ctrlBtnCommence) then {
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
};

private _ctrlBtnClear = _display displayCtrl 8027;
if (!isNull _ctrlBtnClear) then {
	_ctrlBtnClear ctrlEnable _hasObjective;
	if (!_hasObjective) then {
		_ctrlBtnClear ctrlSetTooltip "No active plan to clear.";
	} else {
		_ctrlBtnClear ctrlSetTooltip "";
	};
};

// Update Queue list box
if (!isNull _ctrlQueueList) then { lbClear _ctrlQueueList; };
private _totalMoney = 0;
private _totalHR = 0;

{
	_x params ["_type", "_id", "_special", "_costMoney", "_costHR", "_veh", "_name", "_entry"];
	private _rowLabel = "";
	if (_special == "GarageCrew" && { _veh != "" }) then {
		private _vehCfg = configFile >> "CfgVehicles" >> _veh;
		private _vehDisplay = if (isClass _vehCfg) then { getText (_vehCfg >> "displayName") } else { _veh };
		if (_vehDisplay == "") then { _vehDisplay = _veh; };
		_rowLabel = format ["%1 [%2] (%3 € / %4 HR) - Sp: %5", _name, _vehDisplay, _costMoney, _costHR, _entry];
	} else {
		_rowLabel = format ["%1 (%2 € / %3 HR) - Sp: %4", _name, _costMoney, _costHR, _entry];
	};
	_ctrlQueueList lbAdd _rowLabel;
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
if (!isNull _ctrlCostLabel) then {
	_ctrlCostLabel ctrlSetStructuredText parseText _costText;
	_ctrlCostLabel ctrlCommit 0;
};

// Re-adjust controls group to force recalculation of the vertical scroll range
if (!isNull _controlsGroup) then {
	private _currentPos = ctrlPosition _controlsGroup;
	_controlsGroup ctrlSetPosition [_currentPos # 0, _currentPos # 1, _currentPos # 2, safeZoneH - 14 * _uH];
	_controlsGroup ctrlCommit 0;
};