#include <amxmodx>
#include <cstrike>
#include <engine>
#include <fun>
#include <hamsandwich>
#include <fakemeta>
#include <sqlx>
#include <xs>
#include <reapi>

/* =================================================================================
* 				[ Global stuff ]
* ================================================================================= */

#define PLAYER_ARRAY 				33

#define IsPlayer(%0) 				( 1 <= %0 <= MAX_PLAYERS )

#define GetPlayerBit(%0,%1) 		( IsPlayer(%1) && ( %0 & ( 1 << ( %1 & 31 ) ) ) )
#define SetPlayerBit(%0,%1) 		( IsPlayer(%1) && ( %0 |= ( 1 << ( %1 & 31 ) ) ) )
#define ClearPlayerBit(%0,%1) 		( IsPlayer(%1) && ( %0 &= ~( 1 << ( %1 & 31 ) ) ) )
#define SwitchPlayerBit(%0,%1) 		( IsPlayer(%1) && ( %0 ^= ( 1 << ( %1 & 31 ) ) ) )

#define ClientPlaySound(%0,%1) 		client_cmd( %0, "spk ^"%s^"", %1 )

const TASK_JOIN_TEAM 	= 1000;
const TASK_TIMER 		= 1100;
const TASK_FIX_MENU 	= 1200;
const TASK_ROUND_TIME 	= 1300;

const MAX_ARENAS 		= 16;
const MAX_SPAWNS 		= 8;

const MIN_ROUND_TIME 	= 15;

enum _:Queries
{
	QUERY_LOAD,
	QUERY_INSERT,
	QUERY_IGNORE
}

enum _:Round_Status
{
	ROUND_ENDED,
	ROUND_FROZEN,
	ROUND_STARTED
}

enum _:Arena_Statuses
{
	ARENA_IDLE,
	ARENA_PLAYING,
	ARENA_FINISHED
}

enum _:Arena_Types
{
	ARENA_RIFLE,
	ARENA_SNIPER,
	ARENA_PISTOL,
	ARENA_KNIFE
}

enum _:Cvars
{
	CVAR_PLAYERS,
	CVAR_GAME_DESCRIPTION,
	CVAR_FRAGS,
	CVAR_HIDE_HUD,
	CVAR_ROUND_TIME,
	CVAR_BLOCK_DROP,
	CVAR_BLOCK_RADIO,
	CVAR_BLOCK_KILL,
	CVAR_BLOCK_SPRAY,
	CVAR_SHOW_ACTIVITY
}

enum _:Spawn_Struct
{
	Spawn_Side,
	Float:Spawn_Origin[ 3 ],
	Float:Spawn_Angles[ 3 ]
}

enum _:Message_Struct
{
	Message_Id,
	Message_Arena,
	Message_Origin[ 3 ],
	Message_Data[ 64 ],
	Message_Size
}

enum _:Weapon_Struct
{
	Weapon_Alias[ 32 ],
	Weapon_Name[ 32 ],
	Weapon_Id,
	Weapon_Ammo
}

enum _:Arena_Struct
{
	Arena_Type,
	Arena_Winner,
	Arena_Status,
	Arena_Opponents[ 2 ]
}

enum _:Player_Struct
{
	Player_Name[ 32 ],
	
	Player_Id,
	Player_Arena,
	Player_Spectating,
	Player_Preferences,
	
	Player_Weapon_Primary,
	Player_Weapon_Secondary
}

new const g_sWeapons[ ][ Weapon_Struct ] =
{
	{ "AK-47 Kalashnikov", 		"weapon_ak47", 		CSW_AK47, 		90 	},
	{ "Maverick M4A1 Carbine", 	"weapon_m4a1", 		CSW_M4A1, 		90 	},
	{ "K&M Sub-Machine Gun", 	"weapon_mp5navy", 	CSW_MP5NAVY, 	120 },
	{ "IMI Galil", 				"weapon_galil", 	CSW_GALIL, 		90 	},
	{ "Famas Clarion 5.56", 	"weapon_famas", 	CSW_FAMAS, 		90 	},
	{ "Glock-18", 				"weapon_glock18", 	CSW_GLOCK18, 	120 },
	{ "USP-45 Tactical", 	 	"weapon_usp", 		CSW_USP, 		100 },
	{ "228 Compact", 			"weapon_p228", 		CSW_P228, 		52 	},
	{ "Desert Eagle", 			"weapon_deagle", 	CSW_DEAGLE, 	35 	},
	{ "Five-Seven", 			"weapon_fiveseven", CSW_FIVESEVEN, 	100 },
	{ "Dual Berettas", 			"weapon_elite", 	CSW_ELITE, 		120 }
};

new const g_szWeaponMenuTitles[ ][ ] =
{
	"ELIGE TU ARMA PRIMARIA",
	"ELIGE TU ARMA SECUNDARIA",
	
	"PERMITIR RONDA FRANCOTIRADORES?",
	"PERMITIR RONDA PISTOLAS?",
	"PERMITIR RONDA CUCHILLOS?",
	
	"SILENCIAR M4A1?"
};

new const g_szNumbers[ ][ ] =
{
	"UNO", "DOS", "TRES", "CUATRO",
	"CINCO", "SEIS", "SIETE", "OCHO",
	"NUEVE", "DIEZ", "ONCE", "DOCE",
	"TRECE", "CATORCE", "QUINCE", "DIECISEIS"
};

new const g_szRoundTypes[ ][ ] =
{
	"RIFLES DE ASALTO",
	"FRANCOTIRADORES",
	"PISTOLAS",
	"CUCHILLOS"
};

new const g_szPrefix[ ]			= "Arena";
new const g_szDebris[ ] 		= "debris";
new const g_szFootstep[ ] 		= "player/pl_";
new const g_szKeyName[ ]		= "name";
new const g_szWeaponKnife[ ] 	= "weapon_knife";
new const g_szMessageManager[ ] = "MessageManager";

new g_iIsConnected;
new g_iIsAlive;
new g_iIsLogged;

new g_iRoundStatus;
new g_iMessageManager;
new g_iTimer;
new g_iHudObject;
new g_iMaxPlayers;
new g_iTraceTarget;
new g_iBreakableAttacker;

new g_iArenasCount;
new g_iSpawnsCount;

new g_iHideWeapon;
new g_iRoundTime;
new g_iCrosshair;
new g_iClCorpse;
new g_iScoreInfo;
new g_iShowTimer;

new g_pSpawn;

new g_pCvars[ Cvars ];

new g_sSpawns[ MAX_SPAWNS ][ Spawn_Struct ];
new g_sArenas[ MAX_ARENAS ][ Arena_Struct ];

new g_sPlayers[ PLAYER_ARRAY ][ Player_Struct ];

new Array:g_aMessages;

new Handle:g_hConnection;

/* =================================================================================
* 				[ Plugin events ]
* ================================================================================= */

public plugin_natives( )
{
	register_native( "ar_get_round_time", "_ar_get_round_time" );
	register_native( "ar_get_player_arena", "_ar_get_player_arena" );
}

public plugin_precache( )
{
	CreateMapEntities( );
	
	g_pSpawn = register_forward( FM_Spawn, "OnSpawn_Pre", false );
}

public plugin_init( )
{
	register_plugin( "Arena", "2.0", "Manu" );
	register_cvar( "arena_version", "2.0", ( FCVAR_SERVER | FCVAR_SPONLY ) );
	
	unregister_forward( FM_Spawn, g_pSpawn, false );
	
	RegisterHam( Ham_Spawn, "player", "OnPlayerSpawn_Post", true );
	RegisterHam( Ham_Killed, "player", "OnPlayerKilled_Post", true );
	RegisterHam( Ham_TraceAttack, "player", "OnPlayerTraceAttack_Pre", false );
	RegisterHam( Ham_BloodColor, "player", "OnPlayerBloodColor_Pre", false );
	RegisterHam( Ham_Player_ImpulseCommands, "player", "OnPlayerImpulseCommands_Pre", false );
	
	RegisterHam( Ham_Spawn, "weaponbox", "OnWeaponBoxSpawn_Post", true );
	RegisterHam( Ham_TraceAttack, "func_breakable", "OnBreakableTraceAttack_Pre", false );
	
	register_forward( FM_ClientKill, "OnClientKill_Pre", false );
	register_forward( FM_GetGameDescription, "OnGetGameDescription_Pre", false );
	register_forward( FM_ClientUserInfoChanged, "OnClientUserInfoChanged_Pre", false );
	
	RegisterHookChain( RH_SV_StartSound, "OnStartSound_Pre", false );
	
	register_think( g_szMessageManager, "OnMessageManagerThink" );
	
	register_event( "ResetHUD", "OnResetHUD", "be" );
	register_event( "SpecHealth2", "OnSpecHealth2", "bd" );
	
	register_event( "HLTV", "OnRoundCommencing", "a", "1=0", "2=0" );
	
	register_logevent( "OnRoundEnd", 2, "1=Round_End" );
	register_logevent( "OnRoundStart", 2, "1=Round_Start" );
	
	register_logevent( "OnRoundEnd", 2, "0=World triggered", "1&Restart_Round_" );
	register_logevent( "OnRoundEnd", 2, "0=World triggered", "1=Game_Commencing" );
	
	register_message( SVC_TEMPENTITY, "OnMessageRedirect" );
	
	register_message( get_user_msgid( "Brass" ), "OnMessageRedirect" );
	register_message( get_user_msgid( "ClCorpse" ), "OnMessageRedirect" );
	
	register_message( get_user_msgid( "ShowMenu" ), "OnMessageShowMenu" );
	register_message( get_user_msgid( "VGUIMenu" ), "OnMessageVGUIMenu" );
	
	register_clcmd( "jointeam", "ClientCommand_ChooseTeam" );
	register_clcmd( "chooseteam", "ClientCommand_ChooseTeam" );
	
	register_clcmd( "drop", "ClientCommand_Drop" );
	
	register_clcmd( "say /manage", "ClientCommand_Manage" );
	register_clcmd( "say /configurar", "ClientCommand_Manage" );
	
	register_clcmd( "say guns", "ClientCommand_Weapons" );
	register_clcmd( "say /guns", "ClientCommand_Weapons" );
	register_clcmd( "say armas", "ClientCommand_Weapons" );
	register_clcmd( "say /armas", "ClientCommand_Weapons" );
	
	SQL_Init( );
	SQL_CreateTable( );
	
	Initialize( );
}

public plugin_cfg( )
{
	LoadMapData( );
	LoadConfig( );
	
	set_cvar_num( "mp_freeforall", 1 );
	set_cvar_num( "mp_limitteams", 0 );
	set_cvar_num( "mp_autoteambalance", 0 );
	set_cvar_num( "mp_tkpunish", 0);
	set_cvar_num( "mp_autokick", 0 );
	set_cvar_num( "mp_forcechasecam", 2 );
}

/* =================================================================================
* 				[ Delete Map Entities ]
* ================================================================================= */

public OnSpawn_Pre( iEnt )
{
	if ( !pev_valid( iEnt ) )
	{
		return FMRES_IGNORED;
	}
	
	new const szEntitiesToDelete[ ][ ] =
	{
		"func_bomb_target",
		"info_bomb_target",
		"hostage_entity",
		"monster_scientist",
		"func_hostage_rescue",
		"info_hostage_rescue",
		"info_map_parameters",
		"info_vip_start",
		"func_vip_safetyzone",
		"func_escapezone",
		"func_buyzone"
	};
	
	new szClassname[ 32 ];
	
	pev( iEnt, pev_classname, szClassname, 31 );
	
	for ( new i = 0 ; i < sizeof( szEntitiesToDelete ) ; i++ )
	{
		if ( equal( szClassname, szEntitiesToDelete[ i ] ) )
		{
			engfunc( EngFunc_RemoveEntity, iEnt );
			
			return FMRES_SUPERCEDE;
		}
	}
	
	if ( equal( szClassname, "info_player_start" ) )
	{
		new Float:flOrigin[ 3 ];
		new Float:flAngles[ 3 ];
		
		get_entvar( iEnt, var_origin, flOrigin );
		get_entvar( iEnt, var_angles, flAngles );
		
		engfunc( EngFunc_RemoveEntity, iEnt );
		
		new iSpawn = create_entity( "info_player_deathmatch" );
		
		set_entvar( iSpawn, var_origin, flOrigin );
		set_entvar( iSpawn, var_angles, flAngles );
		
		DispatchSpawn( iSpawn );
	}
	
	return FMRES_IGNORED;
}

/* =================================================================================
* 				[ Events ]
* ================================================================================== */

public OnRoundCommencing( )
{
	CheckGameStatus( );
	
	g_iRoundStatus = ROUND_FROZEN;
	
	ManageWinners( );
	ManageArenas( );
}

public OnRoundStart( )
{
	g_iRoundStatus = ROUND_STARTED;
	
	set_task( 0.9, "OnTaskRoundTime", TASK_ROUND_TIME );
	set_task( 1.0, "OnTaskTimer", TASK_TIMER, .flags = "b" );
}

public OnRoundEnd( )
{
	g_iRoundStatus = ROUND_ENDED;
	
	remove_task( TASK_ROUND_TIME );
	remove_task( TASK_TIMER );
	
	LetWaitingPlayersJoin( );
}

public OnResetHUD( iId )
{
	if ( get_pcvar_num( g_pCvars[ CVAR_HIDE_HUD ] ) == 0 )
	{
		return;
	}
	
	message_begin( MSG_ONE_UNRELIABLE, g_iHideWeapon, _, iId );
	write_byte( ( 1<<5 ) | ( 1<<7 ) );
	message_end( );
	
	message_begin( MSG_ONE_UNRELIABLE, g_iCrosshair, _, iId );
	write_byte( 0 );
	message_end( );
}

public OnSpecHealth2( iId )
{
	new iPlayer = read_data( 2 );
	
	if ( !GetPlayerBit( g_iIsAlive, iPlayer ) || ( g_sPlayers[ iPlayer ][ Player_Arena ] == -1 ) )
	{
		entity_set_int( iId, EV_INT_groupinfo, ( 1<<16 ) );
		
		return;
	}
	
	g_sPlayers[ iId ][ Player_Spectating ] = g_sPlayers[ iPlayer ][ Player_Arena ];
	
	entity_set_int( iId, EV_INT_groupinfo, ( 1<<g_sPlayers[ iPlayer ][ Player_Arena ] ) );
}

/* =================================================================================
* 				[ Messages ]
* ================================================================================= */

public OnMessageRedirect( iMessage, iDest, iId )
{
	if ( g_iRoundStatus != ROUND_STARTED )
	{
		return PLUGIN_CONTINUE;
	}
	
	if ( iMessage == SVC_TEMPENTITY )
	{
		new iType = get_msg_arg_int( 1 );
		
		if ( ( iType != TE_BLOOD ) && ( iType != TE_BLOODSPRITE ) && ( iType != TE_BLOODSTREAM ) && ( iType != TE_STREAK_SPLASH ) )
		{
			return PLUGIN_CONTINUE;
		}
	}
	
	static sMessage[ Message_Struct ];
	
	sMessage[ Message_Id ] = iMessage;
	sMessage[ Message_Arena ] = GetMessageArena( iMessage );
	
	if ( sMessage[ Message_Arena ] == -1 )
	{
		return PLUGIN_CONTINUE;
	}
	
	static Float:flOrigin[ 3 ];
	
	get_msg_origin( flOrigin );
	
	for ( new i = 0 ; i < 3 ; i++ )
	{
		sMessage[ Message_Origin ][ i ] = floatround( flOrigin[ i ] );
	}
	
	SaveMessageData( sMessage );
	
	ArrayPushArray( g_aMessages, sMessage );
	
	entity_set_float( g_iMessageManager, EV_FL_nextthink, get_gametime( ) );
	
	return PLUGIN_HANDLED;
}

public OnMessageShowMenu( iMessage, iDest, iId )
{
	new szData[ 32 ];
	
	get_msg_arg_string( 4, szData, charsmax( szData ) );
	
	if ( containi( szData, "Team_Select" ) == -1 )
	{
		return PLUGIN_CONTINUE;
	}
	
	set_task( 0.1, "OnTaskFixMenu", ( iId + TASK_FIX_MENU ) );
	
	return PLUGIN_HANDLED;
}

public OnMessageVGUIMenu( iMessage, iDest, iId )
{
	new iMenu = get_msg_arg_int( 1 );
	
	if ( iMenu != 2 )
	{
		return PLUGIN_CONTINUE;
	}
	
	set_task( 0.1, "OnTaskFixMenu", ( iId + TASK_FIX_MENU ) );
	
	return PLUGIN_HANDLED;
}

/* =================================================================================
* 				[ Tasks ]
* ================================================================================== */

public OnTaskJoinTeam( iTask )
{
	new iId = ( iTask - TASK_JOIN_TEAM );
	
	if ( !GetPlayerBit( g_iIsConnected, iId ) )
	{
		return;
	}
	
	( g_iRoundStatus != ROUND_ENDED ) ?
		rg_join_team( iId, TEAM_SPECTATOR ) : rg_join_team( iId, TEAM_TERRORIST );
}

public OnTaskFixMenu( iTask )
{
	new iId = ( iTask - TASK_FIX_MENU );
	
	if ( !GetPlayerBit( g_iIsConnected, iId ) )
	{
		return;
	}
	
	set_member( iId, m_iMenu, 0 );
}

public OnTaskTimer( iTask )
{
	if ( --g_iTimer > 0 )
	{
		for ( new iPlayer = 1, iArena = 0, iTarget = 0 ; iPlayer <= g_iMaxPlayers ; iPlayer++ )
		{
			if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
			{
				continue;
			}
			
			if ( !GetPlayerBit( g_iIsAlive, iPlayer ) )
			{
				iTarget = entity_get_int( iPlayer, EV_INT_iuser2 );
				
				if ( !GetPlayerBit( g_iIsAlive, iTarget ) )
				{
					continue;
				}
			}
			else
			{
				iTarget = iPlayer;
			}
			
			iArena = g_sPlayers[ iTarget ][ Player_Arena ];
			
			if ( iArena == -1 )
			{
				continue;
			}
			
			if ( iTarget == iPlayer )
			{
				set_dhudmessage( 250, 170, 50, -1.0, 0.05, 0, 0.0, 1.0, .fadeouttime = 0.0 );
				show_dhudmessage( iPlayer, "ARENA %s^n%s", g_szNumbers[ iArena ], g_szRoundTypes[ g_sArenas[ iArena ][ Arena_Type ] ] );
			}
			else
			{
				set_dhudmessage( 250, 170, 50, -1.0, 0.2, 0, 0.0, 1.0, .fadeouttime = 0.0 );
				show_dhudmessage( iPlayer, "ESPECTEANDO ARENA %s^n%s", g_szNumbers[ iArena ], g_szRoundTypes[ g_sArenas[ iArena ][ Arena_Type ] ] );
			}
		}
		
		return;
	}
	
	new iList[ 2 ];
	
	for ( new iArena = 0, iNum = 0 ; iArena < g_iArenasCount ; iArena++ )
	{
		if ( g_sArenas[ iArena ][ Arena_Status ] != ARENA_PLAYING )
		{
			continue;
		}
		
		if ( GetPlayerBit( g_iIsAlive, g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] ) ) iList[ iNum++ ] = g_sArenas[ iArena ][ Arena_Opponents ][ 0 ];
		if ( GetPlayerBit( g_iIsAlive, g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] ) ) iList[ iNum++ ] = g_sArenas[ iArena ][ Arena_Opponents ][ 1 ];
		
		if ( iNum == 0 )
		{
			continue;
		}
		
		g_sArenas[ iArena ][ Arena_Winner ] = iList[ random( iNum ) ];
		g_sArenas[ iArena ][ Arena_Status ] = ARENA_FINISHED;
		
		while ( iNum > 0 )
		{
			iNum--;
			
			client_print_color( iList[ iNum ], print_team_default, "^4[%s]^1 Se termino el tiempo y el ganador fue elegido al azar.", g_szPrefix );
			client_print_color( iList[ iNum ], print_team_default, "^4[%s]^1 Ganador de la arena:^4 %s^1.", g_szPrefix, g_sPlayers[ g_sArenas[ iArena ][ Arena_Winner ] ][ Player_Name ] );
		}
	}
	
	rg_round_end( 5.0, WINSTATUS_TERRORISTS, ROUND_TERRORISTS_WIN );
	
	remove_task( TASK_TIMER );
	
	return;
}

public OnTaskRoundTime( iTask )
{
	g_iTimer = max( MIN_ROUND_TIME, get_pcvar_num( g_pCvars[ CVAR_ROUND_TIME ] ) );
	
	message_begin( MSG_BROADCAST, g_iShowTimer );
	message_end( );
	
	message_begin( MSG_BROADCAST, g_iRoundTime );
	write_short( g_iTimer );
	message_end( );
}

/* =================================================================================
* 				[ Player Main Events ]
* ================================================================================== */

public OnPlayerSpawn_Post( iId )
{
	if ( !is_user_alive( iId ) )
	{
		return HAM_IGNORED;
	}
	
	SetPlayerBit( g_iIsAlive, iId );
	
	if ( g_sPlayers[ iId ][ Player_Arena ] == -1 )
	{
		SetPlayerVisibility( iId, false );
		
		return HAM_IGNORED;
	}
	
	SetPlayerVisibility( iId, true );
	SetPlayerPosition( iId );
	SetPlayerEquipment( iId );
	
	if ( get_pcvar_num( g_pCvars[ CVAR_BLOCK_RADIO ] ) > 0 )
	{
		set_pdata_int( iId, 192, 0 );
	}
	
	return HAM_IGNORED;
}

public OnPlayerKilled_Post( iVictim, iAttacker, bShouldgib )
{
	ClearPlayerBit( g_iIsAlive, iVictim );
	
	if ( g_iRoundStatus != ROUND_STARTED )
	{
		return HAM_IGNORED;
	}
	
	new iArena = g_sPlayers[ iVictim ][ Player_Arena ];
	
	if ( ( iArena == -1 ) || ( g_sArenas[ iArena ][ Arena_Status ] != ARENA_PLAYING ) )
	{
		return HAM_IGNORED;
	}
	
	set_hudmessage( 250, 210, 40, 0.1, 0.6, 1, 0.5, 5.0 );
	ShowSyncHudMsg( iVictim, g_iHudObject, "Recuerda que puedes elegir tus armas y tus^npreferencias escribiendo guns en el chat" );
	
	if ( !GetPlayerBit( g_iIsAlive, iAttacker ) || ( iVictim == iAttacker ) )
	{
		( g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] == iVictim ) ?
			( iAttacker = g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] ) :
			( iAttacker = g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] );
	}
	
	if ( iArena == 0 )
	{
		new iFrags = ( get_user_frags( iAttacker ) + get_pcvar_num( g_pCvars[ CVAR_FRAGS ] ) );
		
		set_user_frags( iAttacker, iFrags );
		
		message_begin( MSG_BROADCAST, g_iScoreInfo );
		write_byte( iAttacker );
		write_short( iFrags );
		write_short( get_user_deaths( iAttacker ) );
		write_short( 0 );
		write_short( _:TEAM_TERRORIST );
		message_end( );
	}
	
	g_sArenas[ iArena ][ Arena_Winner ] = iAttacker;
	g_sArenas[ iArena ][ Arena_Status ] = ARENA_FINISHED;
	
	if ( get_pcvar_num( g_pCvars[ CVAR_SHOW_ACTIVITY ] ) > 0 )
	{
		client_print_color( 0, print_team_default, "^4[%s]^1 ARENA^3 %s^1:^4 %s^1 le gano a^4 %s^1.",
			g_szPrefix, g_szNumbers[ iArena ], g_sPlayers[ iAttacker ][ Player_Name ], g_sPlayers[ iVictim ][ Player_Name ] );
	}
	
	CheckRoundStatus( );
	
	return HAM_IGNORED;
}

public OnPlayerTraceAttack_Pre( iVictim, iAttacker, Float:flDamage, Float:flDirection[ 3 ], iTrace, iDamageBits )
{
	if ( ( g_iRoundStatus != ROUND_STARTED ) && GetPlayerBit( g_iIsConnected, iAttacker ) )
	{
		return HAM_SUPERCEDE;
	}
	
	g_iTraceTarget = iVictim;
	
	return HAM_IGNORED;
}

public OnPlayerImpulseCommands_Pre( iId )
{
	if ( get_pcvar_num( g_pCvars[ CVAR_BLOCK_SPRAY ] ) == 0 )
	{
		return HAM_IGNORED;
	}
	
	if ( !GetPlayerBit( g_iIsAlive, iId ) || ( entity_get_int( iId, EV_INT_impulse ) != 201 ) )
	{
		return HAM_IGNORED;
	}
	
	entity_set_int( iId, EV_INT_impulse, 0 );
	
	return HAM_HANDLED;
}

public OnPlayerBloodColor_Pre( iId )
{
	SetHamReturnInteger( -1 );
	
	return HAM_SUPERCEDE;
}

/* =================================================================================
* 				[ Weapon forwards ]
* ================================================================================== */

public OnWeaponBoxSpawn_Post( iEnt )
{
	if ( !pev_valid( iEnt ) )
	{
		return HAM_IGNORED;
	}
	
	entity_set_int( iEnt, EV_INT_flags, FL_KILLME );
	
	call_think( iEnt );
	
	return HAM_IGNORED;
}

/* =================================================================================
* 				[ Message Manager ]
* ================================================================================== */

public OnMessageManagerThink( iEnt )
{
	new iMessages = ArraySize( g_aMessages );
	
	for ( new i = 0 ; i < iMessages ; i++ )
	{
		SendSavedMessage( i );
	}
	
	ArrayClear( g_aMessages );
}

/* =================================================================================
* 				[ Sound block & redirect ]
* ================================================================================== */

public OnStartSound_Pre( iRecipients, iEnt, iChannel, const szSample[ ], iVolume, Float:flAttn, iFlags, iPitch )
{
	static iSender; iSender = iEnt;
	
	if ( equal( szSample, g_szDebris, 6 ) )
	{
		iSender = g_iBreakableAttacker;
	}
	
	if ( !GetPlayerBit( g_iIsAlive, iSender ) )
	{
		return HC_CONTINUE;
	}
	
	static iArena; iArena = g_sPlayers[ iSender ][ Player_Arena ];
	
	if ( iArena == -1 )
	{
		return HC_SUPERCEDE;
	}
	
	static iFootstep; iFootstep = equal( szSample, g_szFootstep, 10 );
	
	for ( new iPlayer = 1 ; iPlayer <= g_iMaxPlayers ; iPlayer++ )
	{
		if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
		{
			continue;
		}
		
		if ( g_sPlayers[ iPlayer ][ Player_Spectating ] != iArena )
		{
			continue;
		}
		
		if ( ( iFootstep != 0 ) && ( iPlayer == iSender ) )
		{
			continue;
		}
		
		if ( is_user_bot( iPlayer ) )
		{
			continue;
		}
		
		rh_emit_sound2( iEnt, iPlayer, iChannel, szSample, ( float( iVolume ) / 255.0 ), flAttn, iFlags, iPitch );
	}
	
	return HC_SUPERCEDE;
}

public OnBreakableTraceAttack_Pre( iVictim, iAttacker, Float:flDamage, Float:flDirection[ 3 ], iTrace, iDamageBits )
{
	if ( ( g_iRoundStatus != ROUND_STARTED ) || !GetPlayerBit( g_iIsAlive, iAttacker ) )
	{
		return HAM_IGNORED;
	}
	
	g_iBreakableAttacker = iAttacker;
	
	return HAM_IGNORED;
}

/* =================================================================================
* 				[ Name management ]
* ================================================================================== */

public OnClientUserInfoChanged_Pre( iId, pBuffer ) 
{
	if ( !GetPlayerBit( g_iIsConnected, iId ) )
	{
		return FMRES_IGNORED;
	}
	
	new szName[ 32 ];
	
	engfunc( EngFunc_InfoKeyValue, pBuffer, g_szKeyName, szName, charsmax( szName ) );
	
	if ( equal( szName, g_sPlayers[ iId ][ Player_Name ] ) )
	{
		return FMRES_IGNORED;
	}
	
	if ( GetPlayerBit( g_iIsLogged, iId ) )
	{
		SavePlayerData( iId );
		
		ClearPlayerBit( g_iIsLogged, iId );
	}
	
	copy( g_sPlayers[ iId ][ Player_Name ], charsmax( g_sPlayers[ ][ Player_Name ] ), szName );
	
	LoadPlayerData( iId );
	
	return FMRES_IGNORED;
}

/* =================================================================================
* 				[ Other forwards ]
* ================================================================================== */

public OnClientKill_Pre( iId )
{
	if ( get_pcvar_num( g_pCvars[ CVAR_BLOCK_KILL ] ) > 0 )
	{
		return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED;
}

public OnGetGameDescription_Pre( )
{
	if ( get_pcvar_num( g_pCvars[ CVAR_GAME_DESCRIPTION ] ) > 0 )
	{
		forward_return( FMV_STRING, "Arena" );
		
		return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED;
}

/* =================================================================================
* 				[ Client Connection ]
* ================================================================================== */

public client_putinserver( iId )
{
	SetPlayerBit( g_iIsConnected, iId );
	
	LoadDefaultData( iId );
	LoadPlayerData( iId );
	
	set_task( 1.0, "OnTaskJoinTeam", ( iId + TASK_JOIN_TEAM ) );
	
	CheckGameStatus( );
}

public client_disconnected( iId )
{
	CheckDisconnection( iId );
	
	if ( GetPlayerBit( g_iIsLogged, iId ) )
	{
		SavePlayerData( iId );
	}
	
	ClearPlayerBit( g_iIsConnected, iId );
	ClearPlayerBit( g_iIsAlive, iId );
	ClearPlayerBit( g_iIsLogged, iId );
	
	ClearPlayerData( iId );
	
	remove_task( iId + TASK_JOIN_TEAM );
	remove_task( iId + TASK_FIX_MENU );
	
	CheckRoundStatus( );
}

/* =================================================================================
* 				[ Client Commands ]
* ================================================================================== */

public ClientCommand_Manage( const iId )
{
	if ( ~get_user_flags( iId ) & ADMIN_RCON )
	{
		return PLUGIN_HANDLED;
	}
	
	ShowManagementMenu( iId );
	
	return PLUGIN_HANDLED;
}

public ClientCommand_Weapons( iId )
{
	if ( !GetPlayerBit( g_iIsConnected, iId ) )
	{
		return PLUGIN_HANDLED;
	}
	
	if ( get_pdata_int( iId, 114 ) != 1 )
	{
		return PLUGIN_HANDLED;
	}
	
	ShowWeaponsMenu( iId, 0 );
	
	return PLUGIN_HANDLED;
}

public ClientCommand_Drop( iId )
{
	if ( get_pcvar_num( g_pCvars[ CVAR_BLOCK_DROP ] ) > 0 )
	{
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public ClientCommand_ChooseTeam( iId )
{
	return PLUGIN_HANDLED;
}

/* =================================================================================
 * 				[ Client Menus ]
 * ================================================================================== */

ShowManagementMenu( const iId )
{
	new iMenu = menu_create( "Configuracion", "ManagementMenuHandler" );
	
	menu_additem( iMenu, "Crear spawn \y(LADO A)" );
	menu_additem( iMenu, "Crear spawn \y(LADO B)^n" );
	
	menu_additem( iMenu, "Borrar ultimo spawn^n" );
	
	menu_additem( iMenu, "Guardar" );
	
	menu_setprop( iMenu, MPROP_EXITNAME, "Cancelar" );
	
	menu_display( iId, iMenu );
	
	return PLUGIN_HANDLED;
}

public ManagementMenuHandler( iId, iMenu, iItem )
{
	menu_destroy( iMenu );
	
	if ( iItem == MENU_EXIT )
	{
		return PLUGIN_HANDLED;
	}
	
	ClientPlaySound( iId, "buttons/lightswitch2.wav" );
	
	switch ( iItem )
	{
		case 0, 1:
		{
			if ( g_iSpawnsCount < MAX_SPAWNS )
			{
				new Float:flOrigin[ 3 ];
				new Float:flAngles[ 3 ];
				
				entity_get_vector( iId, EV_VEC_origin, flOrigin );
				entity_get_vector( iId, EV_VEC_v_angle, flAngles );
				
				xs_vec_copy( flOrigin, g_sSpawns[ g_iSpawnsCount ][ Spawn_Origin ] );
				xs_vec_copy( flAngles, g_sSpawns[ g_iSpawnsCount ][ Spawn_Angles ] );
				
				g_sSpawns[ g_iSpawnsCount ][ Spawn_Side ] = iItem;
				
				g_iSpawnsCount++;
			}
			else
			{
				client_print_color( iId, print_team_default, "^4[%s]^1 Numero maximo de spawns alcanzado.", g_szPrefix );
			}
		}
		case 2:
		{
			if ( g_iSpawnsCount > 0 )
			{
				g_iSpawnsCount--;
			}
			else
			{
				client_print_color( iId, print_team_default, "^4[%s]^1 Ya no hay mas spawns para borrar.", g_szPrefix );
			}
		}
		case 3:
		{
			SaveMapData( );
		}
	}
	
	ShowManagementMenu( iId );
	
	return PLUGIN_HANDLED;
}

ShowWeaponsMenu( const iId, const iStep )
{
	new szNum[ 16 ];
	
	new iMenu = menu_create( g_szWeaponMenuTitles[ iStep ], "OnWeaponsMenuHandler" );
	
	if ( iStep < 2 )
	{
		new iStart = ( iStep * 5 );
		new iEnd = ( iStart + ( 5 + ( iStep * 1 ) ) );
		
		for ( new i = iStart ; i < iEnd ; i++ )
		{
			formatex( szNum, charsmax( szNum ), "%d %d", iStep, i );
			
			menu_additem( iMenu, g_sWeapons[ i ][ Weapon_Alias ], szNum );
		}
	}
	else
	{
		num_to_str( iStep, szNum, charsmax( szNum ) );
		
		menu_additem( iMenu, "Si, acepto", szNum );
		menu_additem( iMenu, "No, gracias", szNum );
	}
	
	menu_setprop( iMenu, MPROP_BACKNAME, "Anterior" );
	menu_setprop( iMenu, MPROP_NEXTNAME, "Siguiente" );
	menu_setprop( iMenu, MPROP_EXITNAME, "Cancelar" );
	
	menu_display( iId, iMenu );
	
	return PLUGIN_HANDLED;
}

public OnWeaponsMenuHandler( iId, iMenu, iItem )
{
	if ( iItem == MENU_EXIT )
	{
		menu_destroy( iMenu );
		
		return PLUGIN_HANDLED;
	}
	
	ClientPlaySound( iId, "buttons/lightswitch2.wav" );
	
	new szData[ 16 ];
	
	new iAccess;
	new iCallback;
	
	menu_item_getinfo( iMenu, iItem, iAccess, szData, charsmax( szData ), _, _, iCallback );
	menu_destroy( iMenu );
	
	new szStep[ 4 ];
	new szNum[ 4 ];
	
	parse( szData, szStep, charsmax( szStep ), szNum, charsmax( szNum ) );
	
	new iStep = str_to_num( szStep );
	
	if ( iStep < 2 )
	{
		new iNum = str_to_num( szNum );
		
		( iStep == 0 ) ?
			( g_sPlayers[ iId ][ Player_Weapon_Primary ] = iNum ) :
			( g_sPlayers[ iId ][ Player_Weapon_Secondary ] = iNum );
	}
	else
	{
		new iFlags = ( 1 << ( iStep - 2 ) );
		
		( iItem != 0 ) ?
			( g_sPlayers[ iId ][ Player_Preferences ] &= ~iFlags ) : ( g_sPlayers[ iId ][ Player_Preferences ] |= iFlags );
	}
	
	if ( ( iStep < 4 ) || ( ( iStep == 4 ) && ( g_sPlayers[ iId ][ Player_Weapon_Primary ] == 1 ) ) )
	{
		ShowWeaponsMenu( iId, ( iStep + 1 ) );
	}
	
	return PLUGIN_HANDLED;
}

/* =================================================================================
 * 				[ Initialize ]
 * ================================================================================== */

Initialize( )
{
	g_iRoundStatus 		= ROUND_STARTED;
	
	g_aMessages 		= ArrayCreate( Message_Struct, 1 );
	g_iMaxPlayers 		= get_maxplayers( );
	g_iHudObject 		= CreateHudSyncObj( );
	g_iArenasCount 		= ( ( g_iMaxPlayers / 2 ) + ( g_iMaxPlayers % 2 ) );
	g_iMessageManager 	= create_entity( "info_target" );
	
	g_iHideWeapon		= get_user_msgid( "HideWeapon" );
	g_iRoundTime 		= get_user_msgid( "RoundTime" );
	g_iCrosshair 		= get_user_msgid( "Crosshair" );
	g_iClCorpse 		= get_user_msgid( "ClCorpse" );
	g_iScoreInfo 		= get_user_msgid( "ScoreInfo" );
	g_iShowTimer 		= get_user_msgid( "ShowTimer" );
	
	g_pCvars[ CVAR_PLAYERS ] 			= register_cvar( "ar_min_players", 			"2"  );
	g_pCvars[ CVAR_GAME_DESCRIPTION ] 	= register_cvar( "ar_game_description", 	"1"  );
	g_pCvars[ CVAR_FRAGS ] 				= register_cvar( "ar_frags", 				"2"  );
	g_pCvars[ CVAR_HIDE_HUD ] 			= register_cvar( "ar_hide_hud", 			"1"  );
	g_pCvars[ CVAR_ROUND_TIME ] 		= register_cvar( "ar_round_time", 			"60" );
	g_pCvars[ CVAR_BLOCK_DROP ] 		= register_cvar( "ar_block_drop", 			"1"  );
	g_pCvars[ CVAR_BLOCK_RADIO ] 		= register_cvar( "ar_block_radio", 			"1"  );
	g_pCvars[ CVAR_BLOCK_KILL ] 		= register_cvar( "ar_block_kill", 			"1"  );
	g_pCvars[ CVAR_BLOCK_SPRAY ] 		= register_cvar( "ar_block_spray", 			"1"  );
	g_pCvars[ CVAR_SHOW_ACTIVITY ] 		= register_cvar( "ar_show_activity", 		"1"  );
	
	set_msg_block( get_user_msgid( "Radar" ), BLOCK_SET );
	set_msg_block( get_user_msgid( "ReloadSound" ), BLOCK_SET );
	
	entity_set_string( g_iMessageManager, EV_SZ_classname, g_szMessageManager );
}

/* =================================================================================
 * 				[ Arena Modules ]
 * ================================================================================== */

ManageWinners( )
{
	for ( new iArena = 0, iNum = 0 ; iArena < g_iArenasCount ; iArena++ )
	{
		if ( g_sArenas[ iArena ][ Arena_Status ] != ARENA_FINISHED )
		{
			continue;
		}
		
		for ( iNum = 0 ; iNum < 2 ; iNum++ )
		{
			if ( g_sArenas[ iArena ][ Arena_Opponents ][ iNum ] == 0 )
			{
				continue;
			}
			
			( g_sArenas[ iArena ][ Arena_Winner ] == g_sArenas[ iArena ][ Arena_Opponents ][ iNum ] ) ?
				( g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ iNum ] ][ Player_Arena ] = max( 0, ( iArena - 1 ) ) ) :
				( g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ iNum ] ][ Player_Arena ] = min( ( MAX_ARENAS - 1 ), ( iArena + 1 ) ) );
		}
	}
}

ManageArenas( )
{
	for ( new iArena = 0 ; iArena < MAX_ARENAS ; iArena++ )
	{
		g_sArenas[ iArena ][ Arena_Winner ] = 0;
		g_sArenas[ iArena ][ Arena_Type ] = ARENA_RIFLE;
		g_sArenas[ iArena ][ Arena_Status ] = ARENA_IDLE;
		
		g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] = 0;
		g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] = 0;
	}
	
	new iList[ MAX_PLAYERS ];
	new iListCount;
	
	for ( new iPlayer = 1, i = 0, j = 0 ; iPlayer <= g_iMaxPlayers ; iPlayer++ )
	{
		if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
		{
			continue;
		}
		
		if ( get_pdata_int( iPlayer, 114 ) != 1 )
		{
			continue;
		}
		
		if ( g_sPlayers[ iPlayer ][ Player_Arena ] == -1 )
		{
			g_sPlayers[ iPlayer ][ Player_Arena ] = ( MAX_ARENAS - 1 );
		}
		
		for ( i = 0 ; i < MAX_PLAYERS ; i++ )
		{
			if ( ( iList[ i ] > 0 ) && ( g_sPlayers[ iList[ i ] ][ Player_Arena ] <= g_sPlayers[ iPlayer ][ Player_Arena ] ) )
			{
				continue;
			}
			
			for ( j = iListCount ; j > i ; j-- )
			{
				iList[ j ] = iList[ j - 1 ];
			}
			
			iList[ i ] = iPlayer;
			iListCount++;
			
			break;
		}
	}
	
	g_iArenasCount = ( ( iListCount / 2 ) + ( iListCount % 2 ) );
	
	for ( new iArena = 0 ; iArena < g_iArenasCount ; iArena++ )
	{
		g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] = iList[ ( iArena * 2 ) ];
		g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] = iList[ ( ( iArena * 2 ) + 1 ) ];
		
		g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] ][ Player_Arena ] = iArena;
		
		entity_set_int( g_sArenas[ iArena ][ Arena_Opponents ][ 0 ], EV_INT_groupinfo, ( 1 << iArena ) );
		
		if ( g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] == 0 )
		{
			client_print_color( g_sArenas[ iArena ][ Arena_Opponents ][ 0 ], print_team_default, "^4[%s]^1 No tienes oponente esta ronda.", g_szPrefix );
			
			g_sArenas[ iArena ][ Arena_Winner ] = g_sArenas[ iArena ][ Arena_Opponents ][ 0 ];
			g_sArenas[ iArena ][ Arena_Status ] = ARENA_FINISHED;
			
			break;
		}
		
		g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] ][ Player_Arena ] = iArena;
		
		entity_set_int( g_sArenas[ iArena ][ Arena_Opponents ][ 1 ], EV_INT_groupinfo, ( 1<<iArena ) );
		
		g_sArenas[ iArena ][ Arena_Type ] = GetArenaType( iArena );
		g_sArenas[ iArena ][ Arena_Status ] = ARENA_PLAYING;
		
		client_print_color( g_sArenas[ iArena ][ Arena_Opponents ][ 0 ], print_team_default, "^4[%s]^1 ARENA^3 %s^1. Oponente:^4 %s^1.", g_szPrefix, g_szNumbers[ iArena ], g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] ][ Player_Name ] );
		client_print_color( g_sArenas[ iArena ][ Arena_Opponents ][ 1 ], print_team_default, "^4[%s]^1 ARENA^3 %s^1. Oponente:^4 %s^1.", g_szPrefix, g_szNumbers[ iArena ], g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] ][ Player_Name ] );
	}
}

GetArenaType( const iArena )
{
	new iPreferences = ( ( 1<<0 ) | ( 1<<1 ) | ( 1<<2 ) );
	
	iPreferences &= ( g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] ][ Player_Preferences ] );
	iPreferences &= ( g_sPlayers[ g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] ][ Player_Preferences ] );
	
	new Array:aTypes = ArrayCreate( 1, 1 );
	
	ArrayPushCell( aTypes, 0 );
	
	for ( new i = 0 ; i < ( Arena_Types - 1 ) ; i++ )
	{
		if ( ~iPreferences & ( 1<<i ) )
		{
			continue;
		}
		
		ArrayPushCell( aTypes, ( i + 1 ) );
	}
	
	new iSize = ArraySize( aTypes );
	new iType = ArrayGetCell( aTypes, random( iSize ) );
	
	ArrayDestroy( aTypes );
	
	return iType;
}

/* =================================================================================
 * 				[ Message Management ]
 * ================================================================================== */

GetMessageArena( const iMessage )
{
	if ( iMessage == SVC_TEMPENTITY )
	{
		if ( !GetPlayerBit( g_iIsConnected, g_iTraceTarget ) )
		{
			return -1;
		}
		
		return g_sPlayers[ g_iTraceTarget ][ Player_Arena ];
	}
	
	new iNum = ( iMessage == g_iClCorpse ) ? 12 : 15;
	new iPlayer = get_msg_arg_int( iNum );
	
	if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
	{
		return -1;
	}
	
	return g_sPlayers[ iPlayer ][ Player_Arena ];
}

SaveMessageData( sMessage[ Message_Struct ] )
{	
	new iArgs = get_msg_args( );
	new iSize = 0;
	
	for ( new i = 1, j = 0 ; i <= iArgs ; i++ )
	{
		j = get_msg_argtype( i );
		
		sMessage[ Message_Data ][ iSize++ ] = j;
		
		if ( j == ARG_STRING )
		{
			iSize += get_msg_arg_string( i, sMessage[ Message_Data ][ iSize ], charsmax( sMessage[ Message_Data ] ) - iSize );
			
			sMessage[ Message_Data ][ iSize++ ] = EOS;
		}
		else
		{
			( ( j != ARG_ANGLE ) && ( j != ARG_COORD ) ) ?
				( sMessage[ Message_Data ][ iSize++ ] = get_msg_arg_int( i ) ) :
				( sMessage[ Message_Data ][ iSize++ ] = floatround( get_msg_arg_float( i ) ) );
		}
	}
	
	sMessage[ Message_Size ] = iSize;
}

SendSavedMessage( const iOrder )
{
	static sMessage[ Message_Struct ];
	
	static iOrigin[ 3 ];
	static szString[ 32 ];
	
	ArrayGetArray( g_aMessages, iOrder, sMessage );
		
	for ( new i = 0 ; i < 3 ; i++ )
	{
		iOrigin[ i ] = sMessage[ Message_Origin ][ i ];
	}
		
	for ( new iPlayer = 1, i = 0, j = 0 ; iPlayer <= g_iMaxPlayers ; iPlayer++ )
	{
		if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
		{
			continue;
		}
		
		if ( g_sPlayers[ iPlayer ][ Player_Spectating ] != sMessage[ Message_Arena ] )
		{
			continue;
		}
		
		if ( ( sMessage[ Message_Id ] == g_iClCorpse ) && ( g_sPlayers[ iPlayer ][ Player_Arena ] != sMessage[ Message_Arena ] ) )
		{
			continue;
		}
		
		message_begin( MSG_ONE_UNRELIABLE, sMessage[ Message_Id ], iOrigin, iPlayer );
		
		j = 0;
		i = 0;
		
		while ( j < sMessage[ Message_Size ] )
		{
			i = sMessage[ Message_Data ][ j ];
			
			if ( i == ARG_STRING )
			{
				i = 0;
				
				while ( sMessage[ Message_Data ][ ++j ] != EOS )
				{
					szString[ i++ ] = sMessage[ Message_Data ][ j ];
				}
				
				szString[ i ] = EOS;
				
				write_string( szString );
			}
			else
			{
				j++;
				
				switch ( i )
				{
					case ARG_BYTE: 		write_byte( sMessage[ Message_Data ][ j ] );
					case ARG_CHAR: 		write_char( sMessage[ Message_Data ][ j ] );
					case ARG_SHORT: 	write_short( sMessage[ Message_Data ][ j ] );
					case ARG_LONG: 		write_long( sMessage[ Message_Data ][ j ] );
					case ARG_ANGLE: 	write_angle( sMessage[ Message_Data ][ j ] );
					case ARG_COORD: 	write_coord( sMessage[ Message_Data ][ j ] );
					case ARG_ENTITY: 	write_entity( sMessage[ Message_Data ][ j ] );
				}
			}
			
			j++;
		}
		
		message_end( );
	}
}

/* =================================================================================
 * 				[ Player Data Management ]
 * ================================================================================== */

LoadDefaultData( const iId )
{
	get_user_name( iId, g_sPlayers[ iId ][ Player_Name ], charsmax( g_sPlayers[ ][ Player_Name ] ) );
	
	g_sPlayers[ iId ][ Player_Arena ] = -1;
	g_sPlayers[ iId ][ Player_Spectating ] = -1;
	g_sPlayers[ iId ][ Player_Preferences ] = 7;
	
	g_sPlayers[ iId ][ Player_Weapon_Primary ] = 0;
	g_sPlayers[ iId ][ Player_Weapon_Secondary ] = 5;
	
	entity_set_int( iId, EV_INT_groupinfo, ( 1<<16 ) );
}

LoadPlayerData( const iId )
{
	SQL_Query( iId, QUERY_LOAD, "SELECT * FROM users WHERE name=^"%s^"",
		g_sPlayers[ iId ][ Player_Name ] );
}

SavePlayerData( const iId )
{
	SQL_Query( iId, QUERY_IGNORE, "UPDATE users SET preferences=%d, wprimary=%d, wsecondary=%d WHERE id=%d",
		g_sPlayers[ iId ][ Player_Preferences ], g_sPlayers[ iId ][ Player_Weapon_Primary ],
		g_sPlayers[ iId ][ Player_Weapon_Secondary ], g_sPlayers[ iId ][ Player_Id ] );
}

ClearPlayerData( const iId )
{
	g_sPlayers[ iId ][ Player_Id ] 				= 0;
	
	g_sPlayers[ iId ][ Player_Arena ] 			= -1;
	g_sPlayers[ iId ][ Player_Preferences ] 		= 0;
	
	g_sPlayers[ iId ][ Player_Weapon_Primary ] 	= 0;
	g_sPlayers[ iId ][ Player_Weapon_Secondary ] = 0;
	
	g_sPlayers[ iId ][ Player_Name ][ 0 ] 		= '^0';
}

/* =================================================================================
 * 				[ Spawn Modules ]
 * ================================================================================== */

SetPlayerVisibility( const iId, const bool:bVisible )
{
	if ( bVisible )
	{
		g_sPlayers[ iId ][ Player_Spectating ] = g_sPlayers[ iId ][ Player_Arena ];
		
		entity_set_int( iId, EV_INT_groupinfo, ( 1 << g_sPlayers[ iId ][ Player_Arena ] ) );
		entity_set_int( iId, EV_INT_effects, ( entity_get_int( iId, EV_INT_effects ) & ~EF_NODRAW ) );
	}
	else
	{
		g_sPlayers[ iId ][ Player_Spectating ] = -1;
		
		entity_set_int( iId, EV_INT_groupinfo, ( 1 << 16 ) );
		entity_set_int( iId, EV_INT_effects, ( entity_get_int( iId, EV_INT_effects ) | EF_NODRAW ) );
	}
}

SetPlayerPosition( const iId )
{
	new iArena = g_sPlayers[ iId ][ Player_Arena ];
	new iSide = ( g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] == iId ) ? 0 : 1;
	
	new iAvailable[ MAX_SPAWNS ];
	new iAvailableCount;
	
	for ( new i = 0 ; i < g_iSpawnsCount ; i++ )
	{
		if ( g_sSpawns[ i ][ Spawn_Side ] != iSide )
		{
			continue;
		}
		
		iAvailable[ iAvailableCount++ ] = i;
	}
	
	if ( iAvailableCount == 0 )
	{
		return false;
	}
	
	new iRandom = random( iAvailableCount );
	
	new Float:flOrigin[ 3 ];
	new Float:flAngles[ 3 ];
	
	xs_vec_copy( g_sSpawns[ iAvailable[ iRandom ] ][ Spawn_Origin ], flOrigin );
	xs_vec_copy( g_sSpawns[ iAvailable[ iRandom ] ][ Spawn_Angles ], flAngles );
	
	entity_set_origin( iId, flOrigin );
	entity_set_vector( iId, EV_VEC_angles, flAngles );
	
	return true;
}

SetPlayerEquipment( const iId )
{
	strip_user_weapons( iId );
	
	give_item( iId, g_szWeaponKnife );
	
	switch ( g_sArenas[ g_sPlayers[ iId ][ Player_Arena ] ][ Arena_Type ] )
	{
		case ARENA_RIFLE:
		{
			new iWeapon = g_sPlayers[ iId ][ Player_Weapon_Primary ];
			
			new iEnt = give_item( iId, g_sWeapons[ iWeapon ][ Weapon_Name ] );
			
			cs_set_user_bpammo( iId, g_sWeapons[ iWeapon ][ Weapon_Id ], g_sWeapons[ iWeapon ][ Weapon_Ammo ] );
			cs_set_user_armor( iId, 100, CS_ARMOR_VESTHELM );
			
			if ( ( iWeapon == 1 ) && ( g_sPlayers[ iId ][ Player_Preferences ] & ( 1<<3 ) ) )
			{
				cs_set_weapon_silen( iEnt, true );
			}
		}
		case ARENA_PISTOL:
		{
			new iWeapon = g_sPlayers[ iId ][ Player_Weapon_Secondary ];
			
			give_item( iId, g_sWeapons[ iWeapon ][ Weapon_Name ] );
			
			cs_set_user_bpammo( iId, g_sWeapons[ iWeapon ][ Weapon_Id ], g_sWeapons[ iWeapon ][ Weapon_Ammo ] );
			cs_set_user_armor( iId, 100, CS_ARMOR_KEVLAR );
		}
		case ARENA_SNIPER:
		{
			give_item( iId, "weapon_awp" );
			
			cs_set_user_bpammo( iId, CSW_AWP, 30 );
			cs_set_user_armor( iId, 100, CS_ARMOR_VESTHELM );
		}
	}
}

/* =================================================================================
* 				[ Load & Save: Map Data ]
* ================================================================================= */

LoadConfig( )
{
	new szFile[ 64 ];
	
	get_localinfo( "amxx_configsdir", szFile, charsmax( szFile ) );
	add( szFile, charsmax( szFile ), "/arena.cfg" );
	
	if ( file_exists( szFile ) )
	{
		server_cmd( "exec ^"%s^"", szFile );
	}
}

LoadMapData( )
{
	new szDir[ 64 ];
	
	get_localinfo( "amxx_datadir", szDir, charsmax( szDir ) );
	add( szDir, charsmax( szDir ), "/arena" );
	
	if ( !dir_exists( szDir ) )
	{
		mkdir( szDir );
	}
	
	new szMap[ 32 ];
	new szFile[ 64 ];
	
	get_mapname( szMap, charsmax( szMap ) );
	formatex( szFile, charsmax( szFile ), "%s/%s.dat", szDir, szMap );
	
	if ( !file_exists( szFile ) )
	{
		return;
	}
	
	new iFile = fopen( szFile, "r" );
	
	new szBuffer[ 128 ];
	
	new szTeam[ 4 ];
	
	new szOrigin[ 3 ][ 8 ];
	new szAngles[ 3 ][ 8 ];
	
	new i = 0;
	
	while ( !feof( iFile ) )
	{
		fgets( iFile, szBuffer, charsmax( szBuffer ) );
		trim( szBuffer );
		
		if ( !szBuffer[ 0 ] )
		{
			continue;
		}
		
		parse( szBuffer,
			szTeam, charsmax( szTeam ),
			szOrigin[ 0 ], charsmax( szOrigin[ ] ),
			szOrigin[ 1 ], charsmax( szOrigin[ ] ),
			szOrigin[ 2 ], charsmax( szOrigin[ ] ),
			szAngles[ 0 ], charsmax( szAngles[ ] ),
			szAngles[ 1 ], charsmax( szAngles[ ] ),
			szAngles[ 2 ], charsmax( szAngles[ ] )
		);
		
		g_sSpawns[ g_iSpawnsCount ][ Spawn_Side ] = str_to_num( szTeam );
		
		for ( i = 0 ; i < 3 ; i++ )
		{
			g_sSpawns[ g_iSpawnsCount ][ Spawn_Origin ][ i ] = _:str_to_float( szOrigin[ i ] );
			g_sSpawns[ g_iSpawnsCount ][ Spawn_Angles ][ i ] = _:str_to_float( szAngles[ i ] );
		}
		
		g_iSpawnsCount++;
	}
	
	fclose( iFile );
}

SaveMapData( )
{
	new szDir[ 64 ];
	
	get_localinfo( "amxx_datadir", szDir, charsmax( szDir ) );
	add( szDir, charsmax( szDir ), "/arena" );
	
	if ( !dir_exists( szDir ) )
	{
		mkdir( szDir );
	}
	
	new szMap[ 32 ];
	new szFile[ 64 ];
	
	get_mapname( szMap, charsmax( szMap ) );
	formatex( szFile, charsmax( szFile ), "%s/%s.dat", szDir, szMap );
	
	new iFile = fopen( szFile, "w" );
	
	for ( new i = 0 ; i < g_iSpawnsCount ; i++ )
	{
		fprintf( iFile, "%d %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f^n",
			g_sSpawns[ i ][ Spawn_Side ], g_sSpawns[ i ][ Spawn_Origin ][ 0 ], g_sSpawns[ i ][ Spawn_Origin ][ 1 ], g_sSpawns[ i ][ Spawn_Origin ][ 2 ],
			g_sSpawns[ i ][ Spawn_Angles ][ 0 ], g_sSpawns[ i ][ Spawn_Angles ][ 1 ], g_sSpawns[ i ][ Spawn_Angles ][ 2 ] );
	}
	
	fclose( iFile );
}

/* =================================================================================
* 				[ Game management ]
* ================================================================================= */

CheckGameStatus( )
{
	new iValid = 0;
	new iTotal = 0;
	
	for ( new iPlayer = 1 ; iPlayer <= g_iMaxPlayers ; iPlayer++ )
	{
		if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
		{
			continue;
		}
		
		iTotal++;
		
		if ( is_user_bot( iPlayer ) || ( get_pdata_int( iPlayer, 114 ) == 1 ) )
		{
			iValid++;
		}
	}
	
	new iNum = get_pcvar_num( g_pCvars[ CVAR_PLAYERS ] );
	
	if ( ( iValid >= iNum ) || ( iTotal < iNum ) )
	{
		return;
	}
	
	server_cmd( "sv_restartround 5" );
	
	set_dhudmessage( 250, 170, 50, -1.0, 0.15, 0, 0.0, 5.0 );
	show_dhudmessage( 0, "EL JUEGO ESTA POR COMENZAR" );
}

CheckRoundStatus( )
{
	if ( g_iRoundStatus != ROUND_STARTED )
	{
		return;
	}
	
	for ( new i = 0 ; i < MAX_ARENAS ; i++ )
	{
		if ( g_sArenas[ i ][ Arena_Status ] == ARENA_PLAYING )
		{
			return;
		}
	}
	
	rg_round_end( 5.0, WINSTATUS_TERRORISTS, ROUND_TERRORISTS_WIN );
}

CheckDisconnection( const iId )
{
	new iArena = g_sPlayers[ iId ][ Player_Arena ];
	
	if ( iArena == -1 )
	{
		return;
	}
	
	new iOpponent = 0;
	
	if ( g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] == iId )
	{
		g_sArenas[ iArena ][ Arena_Opponents ][ 0 ] = 0;
		
		iOpponent = g_sArenas[ iArena ][ Arena_Opponents ][ 1 ];
	}
	else
	{
		g_sArenas[ iArena ][ Arena_Opponents ][ 1 ] = 0;
		
		iOpponent = g_sArenas[ iArena ][ Arena_Opponents ][ 0 ];
	}
	
	if ( g_sArenas[ iArena ][ Arena_Status ] == ARENA_FINISHED )
	{
		if ( g_sArenas[ iArena ][ Arena_Winner ] == iId )
		{
			g_sArenas[ iArena ][ Arena_Winner ] = 0;
		}
		
		return;
	}
	
	if ( !GetPlayerBit( g_iIsConnected, iOpponent ) )
	{
		return;
	}
	
	g_sArenas[ iArena ][ Arena_Winner ] = iOpponent;
	g_sArenas[ iArena ][ Arena_Status ] = ARENA_FINISHED;
	
	ClientPlaySound( iOpponent, "fvox/bell.wav" );
	client_print_color( iOpponent, print_team_default, "^4[%s]^1 Ganaste la arena porque tu oponente se fue.", g_szPrefix );
}

/* =====================================================================
 * 				[ Team Management Modules ]
 * ===================================================================== */

LetWaitingPlayersJoin( )
{
	new iPlayers[ 32 ];
	new iPlayersNum;
	
	get_players( iPlayers, iPlayersNum );
	
	if ( iPlayersNum < get_pcvar_num( g_pCvars[ CVAR_PLAYERS ] ) )
	{
		return;
	}
	
	set_cvar_num( "mp_limitteams", 0 );
	
	for ( new i = 0 ; i < iPlayersNum ; i++ )
	{
		if ( get_pdata_int( iPlayers[ i ], 114 ) == 1 )
		{
			continue;
		}
		
		if ( task_exists( iPlayers[ i ] + TASK_JOIN_TEAM ) )
		{
			continue;
		}
		
		set_task( 1.0, "OnTaskJoinTeam", ( iPlayers[ i ] + TASK_JOIN_TEAM ) );
	}
}

/* =====================================================================
 * 				[ Map parameters ]
 * ===================================================================== */

CreateMapEntities( )
{
	new iEnt = create_entity( "info_map_parameters" );
	
	DispatchKeyValue( iEnt, "buying", "3" );
	DispatchSpawn( iEnt );
}

/* =================================================================================
* 				[ Data base ]
* ================================================================================= */

SQL_Init( )
{
	new szType[ 16 ];
	
	SQL_SetAffinity( "sqlite" );
	SQL_GetAffinity( szType, charsmax( szType ) );
	
	if ( !equal( szType, "sqlite" ) ) 
	{
		log_to_file( "sql_error.log", "No se pudo setear la afinidad del driver a SQLite." );
		
		set_fail_state( "Error en la conexion" );
	}
	
	g_hConnection = SQL_MakeDbTuple( "", "", "", "arena" );
}

SQL_CreateTable( )
{
	new szTable[ 512 ];
	new iLen;
	
	iLen += formatex( szTable[ iLen ], charsmax( szTable ) - iLen, "CREATE TABLE IF NOT EXISTS users (" );
	iLen += formatex( szTable[ iLen ], charsmax( szTable ) - iLen, "id INTEGER PRIMARY KEY AUTOINCREMENT," );
	iLen += formatex( szTable[ iLen ], charsmax( szTable ) - iLen, "name VARCHAR( 32 ) UNIQUE COLLATE NOCASE," );
	iLen += formatex( szTable[ iLen ], charsmax( szTable ) - iLen, "preferences INTEGER NOT NULL DEFAULT 0," );
	iLen += formatex( szTable[ iLen ], charsmax( szTable ) - iLen, "wprimary INTEGER NOT NULL DEFAULT 0," );
	iLen += formatex( szTable[ iLen ], charsmax( szTable ) - iLen, "wsecondary INTEGER NOT NULL DEFAULT 0 );" );
	
	new iData[ 2 ];
	
	iData[ 0 ] = 0;
	iData[ 1 ] = QUERY_IGNORE;
	
	SQL_ThreadQuery( g_hConnection, "SQL_QueryHandler", szTable, iData, sizeof( iData ) );
}

SQL_Query( const iPlayer, const iQuery, const szBuffer[ ], any:... )
{
	new iData[ 2 ];
	new szQuery[ 256 ];
	
	iData[ 0 ] = iPlayer;
	iData[ 1 ] = iQuery;
	
	( numargs( ) > 3 ) ?
		vformat( szQuery, charsmax( szQuery ), szBuffer, 4 ) :
		copy( szQuery, charsmax( szQuery ), szBuffer );
	
	SQL_ThreadQuery( g_hConnection, "SQL_QueryHandler", szQuery, iData, sizeof( iData ) );
}
 
public SQL_QueryHandler( iFailState, Handle:hQuery, szError[ ], iErrcode, iData[ ], iDatalen, Float:flTime )
{
	new iId = iData[ 0 ];
	new iQuery = iData[ 1 ];
	
	if ( iFailState < TQUERY_SUCCESS )
	{
		log_to_file( "sql_error.log", "(Code: %d) %s", iErrcode, szError );
		
		return;
	}
	
	if ( ( iQuery == QUERY_IGNORE ) || !GetPlayerBit( g_iIsConnected, iId ) )
	{
		return;
	}
	
	switch ( iQuery )
	{
		case QUERY_LOAD: 
		{
			if ( SQL_NumResults( hQuery ) <= 0 )
			{
				SQL_Query( iId, QUERY_INSERT, "INSERT INTO users ( name ) VALUES ( ^"%s^" )", g_sPlayers[ iId ][ Player_Name ] );
				
				return;
			}
			
			g_sPlayers[ iId ][ Player_Id ] = SQL_ReadResult( hQuery, SQL_FieldNameToNum( hQuery, "id" ) );
			
			g_sPlayers[ iId ][ Player_Preferences ] = SQL_ReadResult( hQuery, SQL_FieldNameToNum( hQuery, "preferences" ) );
			
			g_sPlayers[ iId ][ Player_Weapon_Primary ] 	= SQL_ReadResult( hQuery, SQL_FieldNameToNum( hQuery, "wprimary" ) );
			g_sPlayers[ iId ][ Player_Weapon_Secondary ] = SQL_ReadResult( hQuery, SQL_FieldNameToNum( hQuery, "wsecondary" ) );
			
			SetPlayerBit( g_iIsLogged, iId );
		}
		case QUERY_INSERT:
		{
			g_sPlayers[ iId ][ Player_Id ] = SQL_GetInsertId( hQuery );
			
			g_sPlayers[ iId ][ Player_Preferences ] = 7;
			
			g_sPlayers[ iId ][ Player_Weapon_Primary ] 	= 0;
			g_sPlayers[ iId ][ Player_Weapon_Secondary ] = 5;
			
			SetPlayerBit( g_iIsLogged, iId );
		}
	}
}

/* =====================================================================
 * 				[ Natives ]
 * ===================================================================== */

public _ar_get_round_time( iPlugin, iParams )
{
	if ( iParams != 0 )
	{
		return -1;
	}
	
	if ( g_iRoundStatus != ROUND_STARTED )
	{
		return -1;
	}
	
	return g_iTimer;
}

public _ar_get_player_arena( iPlugin, iParams )
{
	if ( iParams != 1 )
	{
		return -1;
	}
	
	new iPlayer = get_param( 1 );
	
	if ( !GetPlayerBit( g_iIsConnected, iPlayer ) )
	{
		return -1;
	}
	
	return g_sPlayers[ iPlayer ][ Player_Arena ];
}