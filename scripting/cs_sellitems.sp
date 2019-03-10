//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines
#define PLUGIN_DESCRIPTION "Sell items you purchase or pickup in the game for a refund."
#define PLUGIN_VERSION "1.0.1"

#define PLUGIN_TAG "{green}[Sell]{default}"

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <sourcemod-colors>

//ConVars
ConVar convar_Status;
ConVar convar_Percentage;
ConVar convar_RequireBuyZone;
ConVar convar_Advert;
ConVar convar_AllowSell;

//Globals
int g_OriginalOwner[MAX_ENTITY_LIMIT + 1];			//Owner cache.
int g_AdvertCooldown[MAXPLAYERS + 1] = {-1, ...};	//Cooldown cache.

public Plugin myinfo = 
{
	name = "[CSS/CSGO] Sell Items", 
	author = "Keith Warren (Drixevel)", 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "https://github.com/drixevel"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("cs_sellitems.phrases");
	
	CreateConVar("sm_csgo_sellitems_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	convar_Status = CreateConVar("sm_csgo_sellitems_status", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_Percentage = CreateConVar("sm_csgo_sellitems_percentage", "0.50", "Percentage of the original price to give on refunds.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_RequireBuyZone = CreateConVar("sm_csgo_sellitems_requirebuyzone", "1", "Whether to require players to be in a buyzone to sell items.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_Advert = CreateConVar("sm_csgo_sellitems_advert", "1", "Advertise the sell plugin on item purchase with an obvious cooldown.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_AllowSell = CreateConVar("sm_csgo_sellitems_allowsell", "1", "Allow players to sell items dropped by other players or just their items.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	AutoExecConfig();

	RegConsoleCmd("sell", Command_SellItem);
	RegConsoleCmd("sellitem", Command_SellItem);
	RegConsoleCmd("sellweapon", Command_SellItem);
	RegConsoleCmd("sellequipped", Command_SellItem);
	RegConsoleCmd("refund", Command_SellItem);
	RegConsoleCmd("refunditem", Command_SellItem);
	RegConsoleCmd("refundweapon", Command_SellItem);
	RegConsoleCmd("refundequipped", Command_SellItem);

	HookEvent("item_purchase", Event_OnItemPurchase);
}

public void Event_OnItemPurchase(Event event, const char[] name, bool dontBroadcast)
{
	//Check if the plugins active or not and if the advert is enabled or not.
	if (!convar_Status.BoolValue || !convar_Advert.BoolValue)
		return;
	
	//Retrieve client index from the userid.
	int client = GetClientOfUserId(event.GetInt("userid"));

	//Make sure we're valid, in-game and not a bot.
	if (!IsPlayerIndex(client) || !IsClientInGame(client) || IsFakeClient(client))
		return;
	
	//Sets a specified timer of 30 seconds to delay this message so we don't drive players crazy.
	int time = GetTime();
	if (g_AdvertCooldown[client] != -1 && g_AdvertCooldown[client] > time)
		return;
	
	//Update the timer for the client to 30 seconds.
	g_AdvertCooldown[client] = time + 30;

	//SPAM THEM!
	CPrintToChat(client, "%s %T", PLUGIN_TAG, "sell advert on item buy", client);
}

public void OnClientDisconnect_Post(int client)
{
	g_AdvertCooldown[client] = -1;
}

public Action Command_SellItem(int client, int args)
{
	//Plugin is disabled.
	if (!convar_Status.BoolValue)
		return Plugin_Handled;
	
	//Console obviously doesn't have items.
	if (IsClientConsole(client))
	{
		CReplyToCommand(client, "%s %T", PLUGIN_TAG, "Command is in-game only", client);
		return Plugin_Handled;
	}

	//Whether we're required to be in a buyzone or not to sell items.
	if (convar_RequireBuyZone.BoolValue && !GetEntProp(client, Prop_Send, "m_bInBuyZone"))
	{
		CPrintToChat(client, "%s %T", PLUGIN_TAG, "must be in buyzone", client);
		return Plugin_Handled;
	}
	
	//Get the players currently active item.
	int item = GetActiveWeapon(client);

	//Invalid item for whatever reason.
	if (!IsValidEntity(item))
	{
		CPrintToChat(client, "%s %T", PLUGIN_TAG, "no item found", client);
		return Plugin_Handled;
	}

	//Pulled from OnEntityCreated to tell if we own the item or not.
	int original = g_OriginalOwner[item];

	//Check if we're allowed to sell foreign items not bought by us or not.
	if (!convar_AllowSell.BoolValue && original != client)
	{
		CPrintToChat(client, "%s %T", PLUGIN_TAG, "not allowed to sell", client);
		return Plugin_Handled;
	}

	//Get the items classname for use.
	char sItem[32];
	GetEntityClassname(item, sItem, sizeof(sItem));

	//Get the items ID from the entity classname which can be a valid alias.
	CSWeaponID id = CS_AliasToWeaponID(sItem);

	//Get the price of the item originally from the alias.
	int price = CS_GetWeaponPrice(client, id, true);

	//Invalid price, no point in refunding.
	if (price < 1)
	{
		CPrintToChat(client, "%s %T", PLUGIN_TAG, "no price", client);
		return Plugin_Handled;
	}

	//Strip 'weapon_' from the entity name to have a display name.
	StripCharactersPre(sItem, sizeof(sItem), 7);

	//Attempt to remove the item entity, send a print if unsuccessful for whatever reason.
	if (CSGO_RemoveWeaponBySlot(client, GetWeaponSlot(client, item)))
	{
		//Calculate how much to add from the price and the percentage. (0.50 = 50%)
		int add = RoundFloat(FloatDivider(float(price), convar_Percentage.FloatValue));

		//Fuck these hoes.
		CSGO_AddMoney(client, add);
		
		//If client is the original owner, say that otherwise say 'this' weapon instead.
		if (original == client)
			CPrintToChat(client, "%s %T", PLUGIN_TAG, "your item sold", client, sItem, add, price);
		else
			CPrintToChat(client, "%s %T", PLUGIN_TAG, "your item sold", client, sItem, add, price);
	}
	else
		CPrintToChat(client, "%s %T", PLUGIN_TAG, "error removing item", client, sItem);

	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] name)
{
	//If the plugins on and this is a weapon, lets hook spawning.
	if (convar_Status.BoolValue && StrContains(name, "weapon_", false) != -1)
		SDKHook(entity, SDKHook_SpawnPost, OnItemSpawnPost);
}

public void OnItemSpawnPost(int entity)
{
	//I have no idea why we need a 0.1 second delay even though SpawnPost should be plenty of time.
	RequestFrame(Frame_Delay, EntIndexToEntRef(entity));
}

public void Frame_Delay(any entref)
{
	//Turn the reference back into an index and see if it's valid and if it is, cache the owner.
	int entity = -1;
	if ((entity = EntRefToEntIndex(entref)) > 0)
		g_OriginalOwner[entity] = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
}