#include "quakedef.h"
#include "fs.h"
#include "cl_csqc.h"

// cl_parse.c exports this helper for regular file downloads.
qbool CL_CheckOrDownloadFile(char* filename);
extern void CL_UserinfoChanged(char* key, char* string);
extern int CL_ServerMessageCount(int svc);

#define EZCSQC_WEAPONINFO       1
#define EZCSQC_PROJECTILE       2
#define EZCSQC_WEAPONDEF        4

#define FTE_SAMPLE_CLASS_ROCKET    0
#define FTE_SAMPLE_CLASS_GIB       1
#define FTE_SAMPLE_CLASS_PLAYER    2
#define FTE_SAMPLE_CLASS_EXPLOSION 3
#define FTE_SAMPLE_CLASS_NAIL      4

#define PROJECTILE_ORIGIN       (1 << 0)
#define PROJECTILE_MODEL        (1 << 1)
#define PROJECTILE_ANGLES       (1 << 2)
#define PROJECTILE_OWNER        (1 << 3)
#define PROJECTILE_SPAWN_ORIGIN (1 << 4)

#define WEAPONDEF_INIT          (1 << 0)
#define WEAPONDEF_FLAGS         (1 << 1)
#define WEAPONDEF_ANIM          (1 << 2)

#define WEAPONINFO_INDEX        (1 << 0)
#define WEAPONINFO_AMMO_SHELLS  (1 << 1)
#define WEAPONINFO_AMMO_NAILS   (1 << 2)
#define WEAPONINFO_AMMO_ROCKETS (1 << 3)
#define WEAPONINFO_AMMO_CELLS   (1 << 4)
#define WEAPONINFO_ATTACK       (1 << 5)
#define WEAPONINFO_TIMING       (1 << 6)
#define WEAPONINFO_PRED_PING    (1 << 7)

#define WEPPREDANIM_SOUND       0x0001
#define WEPPREDANIM_PROJECTILE  0x0002
#define WEPPREDANIM_BRANCH      0x0040
#define WEPPREDANIM_MOREBYTES   0x0080

#define KTX_WEAPON_INDEX_MAX    16

typedef struct cl_csqc_capability_s {
	const char* name;
	qbool supported;
	const char* note;
} cl_csqc_capability_t;

typedef struct cl_csqc_entity_s {
	qbool present;
	byte type;
	int modelindex;
	int effects;
	int owner_entnum;
	vec3_t s_origin;
	vec3_t velocity;
	vec3_t angles;
	float s_time;
} cl_csqc_entity_t;

typedef struct cl_csqc_weapon_state_s {
	qbool present;
	int impulse;
	int weapon;
	int frame;
	int ammo_shells;
	int ammo_nails;
	int ammo_rockets;
	int ammo_cells;
	float attack_finished;
	float client_time;
	float client_nextthink;
	int client_thinkindex;
	int client_predflags;
	int client_ping;
} cl_csqc_weapon_state_t;

typedef struct cl_csqc_state_s {
	qbool transport_enabled;
	qbool world_loaded;
	qbool csprogs_available;
	qbool csprogs_warned_missing;
	qbool cgamepacket_warned;
	qbool unsized_entities_warned_nonktx;
	qbool server_enable_sent;
	unsigned int csprogs_checksum;
	int csprogs_size;
	char csprogs_name[MAX_QPATH];
	char csprogs_cache_name[MAX_QPATH];
	int weapon_entnum;
	int weapondef_modelindex[KTX_WEAPON_INDEX_MAX];
	cl_csqc_weapon_state_t weapon_state;
	usercmd_t last_input_cmd;
	qbool have_input_cmd;
	int parsed_entity_packets;
	int parsed_sized_entity_packets;
	int parsed_entity_updates;
	int parsed_entity_removes;
	int parsed_cgame_packets;
	int dropped_packets;
	int dropped_unsized_cgame_packets;
	int dropped_unknown_entity_sized;
	int dropped_unknown_entity_unsized;
} cl_csqc_state_t;

static cl_csqc_state_t cl_csqc;
static cl_csqc_entity_t cl_csqc_entities[CL_MAX_EDICTS];
static cvar_t cl_csqc_cvar = { "cl_csqc", "1" };
static cvar_t cl_csqc_allow_unsized_nonktx_cvar = { "cl_csqc_allow_unsized_nonktx", "0" };
static cvar_t cl_csqc_force_enablecmd_ktx_cvar = { "cl_csqc_force_enablecmd_ktx", "0" };
static const cl_csqc_capability_t cl_csqc_capabilities[] = {
	{ "read.byte/short", true, "entity headers + flags" },
	{ "read.coord/angle/float", true, "projectile + weapon payload decode" },
	{ "render.projectile", true, "CSQC projectile entity linking in CL_EmitEntities" },
	{ "render.viewmodel", true, "minimal weapon model/frame override in V_AddViewWeapon" },
	{ "input.frame", true, "last usercmd bridge from CL_SendCmd" },
	{ "event.cgamepacket.sized", true, "safe sized packet consume path" },
	{ "event.cgamepacket.unsized", false, "payload is VM-defined; currently dropped safely" },
	{ "vm.bytecode_execution", false, "no full CSQC VM runtime yet" },
	{ "draw.scripts_and_hud", false, "requires CSQC VM + draw builtin surface" }
};
static const char* cl_csqc_blockers[] = {
	"P1: Add CSQC VM loader/executor for csprogs bytecode.",
	"P1: Implement CSQC draw/event builtins used by FTE sample mods.",
	"P2: Add robust decode bridge for unsized cgamepacket payload variants.",
	"P2: Validate full match flow against live FTE server + KTX package."
};

static void CL_CSQC_Status_f(void);
static void CL_CSQC_WriteStatusSnapshot(const char* reason);
static qbool CL_CSQC_RequireBytes(int packet_end, int bytes, const char* reason);
static void CL_CSQC_SyncActiveUserinfo(void);
static void CL_CSQC_SyncServerEnable(void);
static qbool CL_CSQC_IsKtxServer(void);
static qbool CL_CSQC_AllowUnsizedEntityDecode(void);

static int CL_CSQC_ReadLimit(int packet_end)
{
	return (packet_end >= 0) ? packet_end : net_message.cursize;
}

static void CL_CSQC_DropCurrentMessage(const char* reason)
{
	cl_csqc.dropped_packets++;
	if (reason && reason[0]) {
		Com_Printf("CSQC: dropping current server message (%s)\n", reason);
	}
	msg_badread = false;
	msg_readcount = net_message.cursize;
}

static qbool CL_CSQC_RequireBytes(int packet_end, int bytes, const char* reason)
{
	int limit = CL_CSQC_ReadLimit(packet_end);

	if (bytes < 0 || MSG_GetReadCount() + bytes > limit) {
		CL_CSQC_DropCurrentMessage(reason);
		return false;
	}

	CL_CSQC_WriteStatusSnapshot("entities-parsed");

	return true;
}

static qbool CL_CSQC_FileExists(const char* path)
{
	vfsfile_t* f;
	if (!path || !path[0]) {
		return false;
	}

	f = FS_OpenVFS(path, "rb", FS_ANY);
	if (!f) {
		return false;
	}

	VFS_CLOSE(f);
	return true;
}

static qbool CL_CSQC_ShouldAdvertiseActive(void)
{
	return cl_csqc_cvar.integer && cl_csqc.transport_enabled;
}

static void CL_CSQC_SyncActiveUserinfo(void)
{
	CL_UserinfoChanged("csqcactive", CL_CSQC_ShouldAdvertiseActive() ? "1" : "0");
}

static void CL_CSQC_SendServerCommand(const char* command)
{
	if (!command || !command[0] || cls.state < ca_connected) {
		return;
	}

	Com_DPrintf("CSQC: sending server command \"%s\"\n", command);
	MSG_WriteByte(&cls.netchan.message, clc_stringcmd);
	SZ_Print(&cls.netchan.message, (char*)command);
}

static void CL_CSQC_SyncServerEnable(void)
{
	qbool should_enable = CL_CSQC_ShouldAdvertiseActive() && cl_csqc.csprogs_available && cls.state == ca_active;
	qbool use_enable_command = !CL_CSQC_IsKtxServer() || cl_csqc_force_enablecmd_ktx_cvar.integer;

	// KTX/FTE interop currently relies on userinfo-only gating; explicit enable can terminate the server session.
	if (!use_enable_command) {
		cl_csqc.server_enable_sent = should_enable;
		return;
	}

	if (should_enable && !cl_csqc.server_enable_sent) {
		CL_CSQC_SendServerCommand("enablecsqc");
		cl_csqc.server_enable_sent = true;
	}
	else if (!should_enable && cl_csqc.server_enable_sent) {
		CL_CSQC_SendServerCommand("disablecsqc");
		cl_csqc.server_enable_sent = false;
	}
}

static int CL_CSQC_MapWeaponToModelIndex(int weapon_value)
{
	if (weapon_value >= 0 && weapon_value < KTX_WEAPON_INDEX_MAX && cl_csqc.weapondef_modelindex[weapon_value] > 0) {
		return cl_csqc.weapondef_modelindex[weapon_value];
	}

	if (weapon_value == 0 || weapon_value == IT_AXE) {
		return cl_modelindices[mi_weapon1];
	}
	if (weapon_value == 1 || weapon_value == IT_SHOTGUN) {
		return cl_modelindices[mi_weapon2];
	}
	if (weapon_value == 2 || weapon_value == IT_SUPER_SHOTGUN) {
		return cl_modelindices[mi_weapon3];
	}
	if (weapon_value == 3 || weapon_value == IT_NAILGUN) {
		return cl_modelindices[mi_weapon4];
	}
	if (weapon_value == 4 || weapon_value == IT_SUPER_NAILGUN) {
		return cl_modelindices[mi_weapon5];
	}
	if (weapon_value == 5 || weapon_value == IT_GRENADE_LAUNCHER) {
		return cl_modelindices[mi_weapon6];
	}
	if (weapon_value == 6 || weapon_value == IT_ROCKET_LAUNCHER) {
		return cl_modelindices[mi_weapon7];
	}
	if (weapon_value == 7 || weapon_value == IT_LIGHTNING) {
		return cl_modelindices[mi_weapon8];
	}

	return 0;
}

static void CL_CSQC_RequestCsprogsIfMissing(void)
{
	char dl_name[MAX_QPATH];

	if (!cl_csqc.transport_enabled || cl_csqc.csprogs_available || cls.state < ca_connected || cls.download) {
		return;
	}

	if (cls.downloadtype != dl_none && cls.downloadtype != dl_single) {
		return;
	}

	if (!cl_csqc.csprogs_name[0]) {
		return;
	}

	cls.downloadtype = dl_single;
	cls.downloadnumber = 0;
	strlcpy(dl_name, cl_csqc.csprogs_name, sizeof(dl_name));
	if (!CL_CheckOrDownloadFile(dl_name)) {
		return;
	}

	// If CL_CheckOrDownloadFile didn't start a download, it either exists already or is blocked.
	cl_csqc.csprogs_available = CL_CSQC_FileExists(cl_csqc.csprogs_name) || CL_CSQC_FileExists(cl_csqc.csprogs_cache_name);
}

static qbool CL_CSQC_ParseProjectilePayload(cl_csqc_entity_t* entity, qbool store, int packet_end)
{
	int sendflags;
	int owner = 0;
	int limit;
	vec3_t origin, velocity, angles;
	float send_time = 0;

	if (!CL_CSQC_RequireBytes(packet_end, 1, "projectile sendflags")) {
		return false;
	}
	sendflags = MSG_ReadByte();

	VectorCopy(entity->s_origin, origin);
	VectorCopy(entity->velocity, velocity);
	VectorCopy(entity->angles, angles);
	send_time = entity->s_time;
	owner = entity->owner_entnum;

	if (sendflags & PROJECTILE_ORIGIN) {
		if (!CL_CSQC_RequireBytes(packet_end, 6 * msg_coordsize + 4, "projectile origin block")) {
			return false;
		}
		origin[0] = MSG_ReadCoord();
		origin[1] = MSG_ReadCoord();
		origin[2] = MSG_ReadCoord();

		velocity[0] = MSG_ReadCoord();
		velocity[1] = MSG_ReadCoord();
		velocity[2] = MSG_ReadCoord();
		send_time = MSG_ReadFloat();
	}

	if (sendflags & PROJECTILE_MODEL) {
		if (!CL_CSQC_RequireBytes(packet_end, 4, "projectile model block")) {
			return false;
		}
		entity->modelindex = MSG_ReadShort();
		entity->effects = MSG_ReadShort();
	}

	if (sendflags & PROJECTILE_ANGLES) {
		int required = 3 * msg_anglesize;
		int available;

		limit = CL_CSQC_ReadLimit(packet_end);
		available = limit - MSG_GetReadCount();

		if (available >= required) {
			angles[0] = MSG_ReadAngle();
			angles[1] = MSG_ReadAngle();
			angles[2] = MSG_ReadAngle();
		}
		else if (packet_end < 0 && !CL_CSQC_IsKtxServer() && cl_csqc_allow_unsized_nonktx_cvar.integer && available >= 3) {
			// Some non-KTX unsized streams still emit byte-angle triplets under 16-bit protocol angle settings.
			angles[0] = MSG_ReadChar() * (360.0f / 256.0f);
			angles[1] = MSG_ReadChar() * (360.0f / 256.0f);
			angles[2] = MSG_ReadChar() * (360.0f / 256.0f);
		}
		else if (!CL_CSQC_RequireBytes(packet_end, required, "projectile angles block")) {
			return false;
		}
	}

	if (sendflags & PROJECTILE_OWNER) {
		if (!CL_CSQC_RequireBytes(packet_end, 2, "projectile owner block")) {
			return false;
		}
		owner = MSG_ReadShort();
	}

	if (sendflags & PROJECTILE_SPAWN_ORIGIN) {
		if (!CL_CSQC_RequireBytes(packet_end, 3 * msg_coordsize, "projectile spawn-origin block")) {
			return false;
		}
		MSG_ReadCoord();
		MSG_ReadCoord();
		MSG_ReadCoord();
	}

	if (msg_badread) {
		CL_CSQC_DropCurrentMessage("projectile payload read");
		return false;
	}

	if (store) {
		VectorCopy(origin, entity->s_origin);
		VectorCopy(velocity, entity->velocity);
		VectorCopy(angles, entity->angles);
		entity->s_time = send_time;
		entity->owner_entnum = owner;
	}

	return true;
}

static qbool CL_CSQC_ParseFteSampleEntityPayload(cl_csqc_entity_t* entity, qbool store, byte class_type, int packet_end)
{
	vec3_t origin;
	vec3_t angles;
	vec3_t forward;
	float speed = 0;
	int modelindex = 0;

	switch (class_type) {
	case FTE_SAMPLE_CLASS_ROCKET:
		if (!CL_CSQC_RequireBytes(packet_end, 3 * msg_coordsize + 4, "fte sample rocket payload")) {
			return false;
		}
		origin[0] = MSG_ReadCoord();
		origin[1] = MSG_ReadCoord();
		origin[2] = MSG_ReadCoord();
		angles[0] = MSG_ReadShort() * (360.0f / 65535.0f);
		angles[1] = MSG_ReadShort() * (360.0f / 65535.0f);
		angles[2] = 0;
		speed = 1000.0f;
		modelindex = cl_modelindices[mi_rocket];
		break;
	case FTE_SAMPLE_CLASS_NAIL:
		if (!CL_CSQC_RequireBytes(packet_end, 3 * msg_coordsize + 7, "fte sample nail payload")) {
			return false;
		}
		origin[0] = MSG_ReadCoord();
		origin[1] = MSG_ReadCoord();
		origin[2] = MSG_ReadCoord();
		modelindex = MSG_ReadByte();
		speed = (float)(short)MSG_ReadShort();
		angles[0] = MSG_ReadShort() * (360.0f / 65535.0f);
		angles[1] = MSG_ReadShort() * (360.0f / 65535.0f);
		angles[2] = 0;
		break;
	case FTE_SAMPLE_CLASS_PLAYER:
		{
			int effects;
			if (!CL_CSQC_RequireBytes(packet_end, 1 + 1 + 1 + (3 * msg_coordsize) + 6 + 1, "fte sample player payload")) {
				return false;
			}
			MSG_ReadByte(); // frame
			MSG_ReadChar(); // pitch
			MSG_ReadChar(); // yaw
			MSG_ReadCoord();
			MSG_ReadCoord();
			MSG_ReadCoord();
			MSG_ReadShort();
			MSG_ReadShort();
			MSG_ReadShort();
			effects = MSG_ReadByte();
			if (effects & 16) {
				if (!CL_CSQC_RequireBytes(packet_end, 1, "fte sample player movetype payload")) {
					return false;
				}
				MSG_ReadByte();
			}
			if (store) {
				memset(entity, 0, sizeof(*entity));
			}
		}
		return !msg_badread;
	case FTE_SAMPLE_CLASS_GIB:
		if (!CL_CSQC_RequireBytes(packet_end, 2 + (3 * msg_coordsize), "fte sample gib payload")) {
			return false;
		}
		MSG_ReadByte();
		MSG_ReadByte();
		MSG_ReadCoord();
		MSG_ReadCoord();
		MSG_ReadCoord();
		if (store) {
			memset(entity, 0, sizeof(*entity));
		}
		return !msg_badread;
	case FTE_SAMPLE_CLASS_EXPLOSION:
		if (!CL_CSQC_RequireBytes(packet_end, 3 * msg_coordsize, "fte sample explosion payload")) {
			return false;
		}
		MSG_ReadCoord();
		MSG_ReadCoord();
		MSG_ReadCoord();
		if (store) {
			memset(entity, 0, sizeof(*entity));
		}
		return !msg_badread;
	default:
		CL_CSQC_DropCurrentMessage("unsupported non-ktx unsized class type");
		return false;
	}

	if (msg_badread) {
		CL_CSQC_DropCurrentMessage("fte sample payload read");
		return false;
	}

	if (!store) {
		return true;
	}

	memset(entity, 0, sizeof(*entity));
	entity->present = true;
	entity->type = EZCSQC_PROJECTILE;
	entity->modelindex = modelindex;
	entity->effects = 0;
	entity->owner_entnum = 0;
	VectorCopy(origin, entity->s_origin);
	VectorCopy(angles, entity->angles);
	entity->s_time = (float)cl.time;
	AngleVectors(angles, forward, NULL, NULL);
	VectorScale(forward, speed, entity->velocity);

	return true;
}

static qbool CL_CSQC_ParseWeaponInfoPayload(int entnum, int packet_end)
{
	int sendflags;
	cl_csqc_weapon_state_t* ws = &cl_csqc.weapon_state;

	if (!CL_CSQC_RequireBytes(packet_end, 1, "weaponinfo sendflags")) {
		return false;
	}
	sendflags = MSG_ReadByte();

	ws->present = true;
	cl_csqc.weapon_entnum = entnum;

	if (sendflags & WEAPONINFO_INDEX) {
		if (!CL_CSQC_RequireBytes(packet_end, 2, "weaponinfo index block")) {
			return false;
		}
		ws->impulse = MSG_ReadByte();
		ws->weapon = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_AMMO_SHELLS) {
		if (!CL_CSQC_RequireBytes(packet_end, 1, "weaponinfo shells block")) {
			return false;
		}
		ws->ammo_shells = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_AMMO_NAILS) {
		if (!CL_CSQC_RequireBytes(packet_end, 1, "weaponinfo nails block")) {
			return false;
		}
		ws->ammo_nails = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_AMMO_ROCKETS) {
		if (!CL_CSQC_RequireBytes(packet_end, 1, "weaponinfo rockets block")) {
			return false;
		}
		ws->ammo_rockets = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_AMMO_CELLS) {
		if (!CL_CSQC_RequireBytes(packet_end, 1, "weaponinfo cells block")) {
			return false;
		}
		ws->ammo_cells = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_ATTACK) {
		if (!CL_CSQC_RequireBytes(packet_end, 9, "weaponinfo attack block")) {
			return false;
		}
		ws->attack_finished = MSG_ReadFloat();
		ws->client_nextthink = MSG_ReadFloat();
		ws->client_thinkindex = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_TIMING) {
		if (!CL_CSQC_RequireBytes(packet_end, 5, "weaponinfo timing block")) {
			return false;
		}
		ws->client_time = MSG_ReadFloat();
		ws->frame = MSG_ReadByte();
	}

	if (sendflags & WEAPONINFO_PRED_PING) {
		if (!CL_CSQC_RequireBytes(packet_end, 2, "weaponinfo pred/ping block")) {
			return false;
		}
		ws->client_predflags = MSG_ReadByte();
		ws->client_ping = MSG_ReadByte();
	}

	if (msg_badread) {
		CL_CSQC_DropCurrentMessage("weaponinfo payload read");
		return false;
	}

	return true;
}

static qbool CL_CSQC_ParseWeaponDefPayload(int packet_end)
{
	int sendflags;
	int weapon_index;

	if (!CL_CSQC_RequireBytes(packet_end, 2, "weapondef header")) {
		return false;
	}
	sendflags = MSG_ReadByte();
	weapon_index = MSG_ReadByte();

	if (sendflags & WEAPONDEF_INIT) {
		if (!CL_CSQC_RequireBytes(packet_end, 4, "weapondef init block")) {
			return false;
		}
		MSG_ReadShort();
		if (weapon_index >= 0 && weapon_index < KTX_WEAPON_INDEX_MAX) {
			cl_csqc.weapondef_modelindex[weapon_index] = MSG_ReadShort();
		}
		else {
			MSG_ReadShort();
		}
	}

	if (sendflags & WEAPONDEF_FLAGS) {
		if (!CL_CSQC_RequireBytes(packet_end, 2, "weapondef flags block")) {
			return false;
		}
		MSG_ReadByte();
		MSG_ReadByte();
	}

	if (sendflags & WEAPONDEF_ANIM) {
		int anim_count;
		int i;

		if (!CL_CSQC_RequireBytes(packet_end, 1, "weapondef anim count")) {
			return false;
		}
		anim_count = MSG_ReadByte();

		for (i = 0; i < anim_count; ++i) {
			int anim_flags;

			if (!CL_CSQC_RequireBytes(packet_end, 2, "weapondef anim header")) {
				return false;
			}
			MSG_ReadByte();
			anim_flags = MSG_ReadByte();

			if (anim_flags & WEPPREDANIM_MOREBYTES) {
				if (!CL_CSQC_RequireBytes(packet_end, 1, "weapondef anim extra flags")) {
					return false;
				}
				anim_flags |= MSG_ReadByte() << 8;
			}

			if (anim_flags & WEPPREDANIM_SOUND) {
				if (!CL_CSQC_RequireBytes(packet_end, 4, "weapondef anim sound block")) {
					return false;
				}
				MSG_ReadShort();
				MSG_ReadShort();
			}

			if (anim_flags & WEPPREDANIM_PROJECTILE) {
				if (!CL_CSQC_RequireBytes(packet_end, 11, "weapondef anim projectile block")) {
					return false;
				}
				MSG_ReadShort();
				MSG_ReadShort();
				MSG_ReadShort();
				MSG_ReadShort();
				MSG_ReadByte();
				MSG_ReadByte();
				MSG_ReadByte();
			}

			if (!CL_CSQC_RequireBytes(packet_end, 1, "weapondef anim frame block")) {
				return false;
			}
			MSG_ReadByte();

			if (anim_flags & WEPPREDANIM_BRANCH) {
				if (!CL_CSQC_RequireBytes(packet_end, 1, "weapondef anim branch block")) {
					return false;
				}
				MSG_ReadByte();
			}

			if (!CL_CSQC_RequireBytes(packet_end, 1, "weapondef anim terminator block")) {
				return false;
			}
			MSG_ReadByte();
		}
	}

	if (msg_badread) {
		CL_CSQC_DropCurrentMessage("weapondef payload read");
		return false;
	}

	return true;
}

static void CL_CSQC_Status_f(void)
{
	size_t i;
	int svc;
	const char* csprogs_label = "none";
	const char* csqcactive_userinfo = Info_ValueForKey(cls.userinfo, "csqcactive");
	qbool has_local_csprogs;
	qbool has_cached_csprogs;

	has_local_csprogs = CL_CSQC_FileExists(cl_csqc.csprogs_name);
	has_cached_csprogs = CL_CSQC_FileExists(cl_csqc.csprogs_cache_name);

	if (cl_csqc.csprogs_name[0]) {
		csprogs_label = cl_csqc.csprogs_name;
	}

	Com_Printf("CSQC status:\n");
	Com_Printf("  transport: %s (cvar=%d pext=%s world=%s)\n",
		cl_csqc.transport_enabled ? "enabled" : "disabled",
		cl_csqc_cvar.integer,
		(cls.fteprotocolextensions & FTE_PEXT_CSQC) ? "yes" : "no",
		cl_csqc.world_loaded ? "yes" : "no");
	Com_Printf("  server cmd: enable_sent=%s\n", cl_csqc.server_enable_sent ? "yes" : "no");
	Com_Printf("  userinfo: csqcactive=%s\n", csqcactive_userinfo[0] ? csqcactive_userinfo : "<unset>");
	Com_Printf("  csprogs: name=%s checksum=%u size=%d local=%s cached=%s\n",
		csprogs_label,
		cl_csqc.csprogs_checksum,
		cl_csqc.csprogs_size,
		has_local_csprogs ? "yes" : "no",
		has_cached_csprogs ? "yes" : "no");
	Com_Printf("  parse stats: entity_packets=%d sized_entity_packets=%d updates=%d removes=%d cgame_packets=%d\n",
		cl_csqc.parsed_entity_packets,
		cl_csqc.parsed_sized_entity_packets,
		cl_csqc.parsed_entity_updates,
		cl_csqc.parsed_entity_removes,
		cl_csqc.parsed_cgame_packets);
	Com_Printf("  msg counters: csqcentities=%d csqcentities_sized=%d cgamepacket=%d cgamepacket_sized=%d\n",
		CL_ServerMessageCount(svc_fte_csqcentities),
		CL_ServerMessageCount(svc_fte_csqcentities_sized),
		CL_ServerMessageCount(svc_fte_cgamepacket),
		CL_ServerMessageCount(svc_fte_cgamepacket_sized));
	Com_Printf("  drops: total=%d unknown_sized=%d unknown_unsized=%d unsized_cgamepacket=%d\n",
		cl_csqc.dropped_packets,
		cl_csqc.dropped_unknown_entity_sized,
		cl_csqc.dropped_unknown_entity_unsized,
		cl_csqc.dropped_unsized_cgame_packets);
	Com_Printf("  svc(70-100):");
	for (svc = 70; svc <= 100; ++svc) {
		int count = CL_ServerMessageCount(svc);
		if (count > 0) {
			Com_Printf(" %d=%d", svc, count);
		}
	}
	Com_Printf("\n");

	Com_Printf("  capability map:\n");
	for (i = 0; i < sizeof(cl_csqc_capabilities) / sizeof(cl_csqc_capabilities[0]); ++i) {
		Com_Printf("    %s: %s (%s)\n",
			cl_csqc_capabilities[i].name,
			cl_csqc_capabilities[i].supported ? "supported" : "unsupported",
			cl_csqc_capabilities[i].note);
	}

	Com_Printf("  priority blockers:\n");
	for (i = 0; i < sizeof(cl_csqc_blockers) / sizeof(cl_csqc_blockers[0]); ++i) {
		Com_Printf("    %s\n", cl_csqc_blockers[i]);
	}

	CL_CSQC_WriteStatusSnapshot("console-command");
}

static void CL_CSQC_WriteStatusSnapshot(const char* reason)
{
	char path[MAX_OSPATH];
	int svc;
	const char* csprogs_label = "none";
	const char* csqcactive_userinfo = Info_ValueForKey(cls.userinfo, "csqcactive");
	qbool has_local_csprogs;
	qbool has_cached_csprogs;
	FILE* f;
	size_t i;

	snprintf(path, sizeof(path), "%s/qw/csqc_status_last.txt", com_basedir);
	FS_CreatePath(path);

	f = fopen(path, "w");
	if (!f) {
		return;
	}

	has_local_csprogs = CL_CSQC_FileExists(cl_csqc.csprogs_name);
	has_cached_csprogs = CL_CSQC_FileExists(cl_csqc.csprogs_cache_name);
	if (cl_csqc.csprogs_name[0]) {
		csprogs_label = cl_csqc.csprogs_name;
	}

	fprintf(f, "reason=%s\n", reason ? reason : "unknown");
	fprintf(f, "cls_state=%d server=%s\n", cls.state, cls.servername);
	fprintf(f, "transport=%s cvar=%d pext=%s world=%s\n",
		cl_csqc.transport_enabled ? "enabled" : "disabled",
		cl_csqc_cvar.integer,
		(cls.fteprotocolextensions & FTE_PEXT_CSQC) ? "yes" : "no",
		cl_csqc.world_loaded ? "yes" : "no");
	fprintf(f, "server enable_sent=%s\n", cl_csqc.server_enable_sent ? "yes" : "no");
	fprintf(f, "userinfo csqcactive=%s\n", csqcactive_userinfo[0] ? csqcactive_userinfo : "<unset>");
	fprintf(f, "csprogs name=%s checksum=%u size=%d local=%s cached=%s\n",
		csprogs_label,
		cl_csqc.csprogs_checksum,
		cl_csqc.csprogs_size,
		has_local_csprogs ? "yes" : "no",
		has_cached_csprogs ? "yes" : "no");
	fprintf(f, "parse entity_packets=%d sized_entity_packets=%d updates=%d removes=%d cgame_packets=%d\n",
		cl_csqc.parsed_entity_packets,
		cl_csqc.parsed_sized_entity_packets,
		cl_csqc.parsed_entity_updates,
		cl_csqc.parsed_entity_removes,
		cl_csqc.parsed_cgame_packets);
	fprintf(f, "messages csqcentities=%d csqcentities_sized=%d cgamepacket=%d cgamepacket_sized=%d\n",
		CL_ServerMessageCount(svc_fte_csqcentities),
		CL_ServerMessageCount(svc_fte_csqcentities_sized),
		CL_ServerMessageCount(svc_fte_cgamepacket),
		CL_ServerMessageCount(svc_fte_cgamepacket_sized));
	fprintf(f, "drops total=%d unknown_sized=%d unknown_unsized=%d unsized_cgamepacket=%d\n",
		cl_csqc.dropped_packets,
		cl_csqc.dropped_unknown_entity_sized,
		cl_csqc.dropped_unknown_entity_unsized,
		cl_csqc.dropped_unsized_cgame_packets);
	fprintf(f, "messages70_100");
	for (svc = 70; svc <= 100; ++svc) {
		int count = CL_ServerMessageCount(svc);
		if (count > 0) {
			fprintf(f, " %d=%d", svc, count);
		}
	}
	fprintf(f, "\n");

	fprintf(f, "capabilities:\n");
	for (i = 0; i < sizeof(cl_csqc_capabilities) / sizeof(cl_csqc_capabilities[0]); ++i) {
		fprintf(f, "  %s: %s (%s)\n",
			cl_csqc_capabilities[i].name,
			cl_csqc_capabilities[i].supported ? "supported" : "unsupported",
			cl_csqc_capabilities[i].note);
	}

	fprintf(f, "blockers:\n");
	for (i = 0; i < sizeof(cl_csqc_blockers) / sizeof(cl_csqc_blockers[0]); ++i) {
		fprintf(f, "  %s\n", cl_csqc_blockers[i]);
	}

	fclose(f);
}

void CL_CSQC_Init(void)
{
	Cvar_Register(&cl_csqc_cvar);
	Cvar_Register(&cl_csqc_allow_unsized_nonktx_cvar);
	Cvar_Register(&cl_csqc_force_enablecmd_ktx_cvar);
	Cmd_AddCommand("cl_csqc_status", CL_CSQC_Status_f);
	CL_CSQC_ClearState();
	CL_CSQC_WriteStatusSnapshot("init");
}

void CL_CSQC_Shutdown(void)
{
	Cmd_RemoveCommand("cl_csqc_status");
	CL_CSQC_ClearState();
}

void CL_CSQC_ClearState(void)
{
	if (cl_csqc.server_enable_sent) {
		CL_CSQC_SendServerCommand("disablecsqc");
	}

	memset(&cl_csqc, 0, sizeof(cl_csqc));
	memset(cl_csqc_entities, 0, sizeof(cl_csqc_entities));
	cl_csqc.weapon_entnum = -1;
	CL_CSQC_SyncActiveUserinfo();
}

void CL_CSQC_ServerInfoChanged(void)
{
	char checksum[MAX_INFO_KEY];
	char size[MAX_INFO_KEY];
	char name[MAX_QPATH];
	unsigned int csprogs_checksum = 0;
	qbool transport_available;

	strlcpy(checksum, Info_ValueForKey(cl.serverinfo, "*csprogs"), sizeof(checksum));
	strlcpy(size, Info_ValueForKey(cl.serverinfo, "*csprogssize"), sizeof(size));
	strlcpy(name, Info_ValueForKey(cl.serverinfo, "*csprogsname"), sizeof(name));

	cl_csqc.transport_enabled = false;
	cl_csqc.csprogs_available = false;
	cl_csqc.csprogs_checksum = 0;
	cl_csqc.csprogs_size = 0;
	cl_csqc.csprogs_name[0] = 0;
	cl_csqc.csprogs_cache_name[0] = 0;
	cl_csqc.csprogs_warned_missing = false;
	CL_CSQC_SyncActiveUserinfo();
	CL_CSQC_SyncServerEnable();

	transport_available = cl_csqc_cvar.integer && (cls.fteprotocolextensions & FTE_PEXT_CSQC);
	if (!transport_available || !checksum[0]) {
		return;
	}

	csprogs_checksum = (unsigned int)strtoul(checksum, NULL, 0);
	if (!csprogs_checksum) {
		return;
	}

	cl_csqc.transport_enabled = true;
	cl_csqc.csprogs_checksum = csprogs_checksum;
	cl_csqc.csprogs_size = Q_atoi(size);

	if (name[0]) {
		strlcpy(cl_csqc.csprogs_name, name, sizeof(cl_csqc.csprogs_name));
	}
	else {
		strlcpy(cl_csqc.csprogs_name, "csprogs.dat", sizeof(cl_csqc.csprogs_name));
	}

	snprintf(cl_csqc.csprogs_cache_name, sizeof(cl_csqc.csprogs_cache_name), "csprogsvers/%x.dat", cl_csqc.csprogs_checksum);

	cl_csqc.csprogs_available = CL_CSQC_FileExists(cl_csqc.csprogs_name) || CL_CSQC_FileExists(cl_csqc.csprogs_cache_name);
	if (!cl_csqc.csprogs_available) {
		CL_CSQC_RequestCsprogsIfMissing();
		cl_csqc.csprogs_available = CL_CSQC_FileExists(cl_csqc.csprogs_name) || CL_CSQC_FileExists(cl_csqc.csprogs_cache_name);
	}

	CL_CSQC_SyncActiveUserinfo();
	CL_CSQC_SyncServerEnable();
	CL_CSQC_WriteStatusSnapshot("serverinfo-changed");
}

void CL_CSQC_WorldLoaded(void)
{
	cl_csqc.world_loaded = true;
	CL_CSQC_RequestCsprogsIfMissing();
	if (!cl_csqc.csprogs_available && !cl_csqc.csprogs_warned_missing && cl_csqc.transport_enabled) {
		cl_csqc.csprogs_warned_missing = true;
		Com_Printf("CSQC: server advertises %s (checksum %u) but it is not available locally yet.\n", cl_csqc.csprogs_name, cl_csqc.csprogs_checksum);
	}

	CL_CSQC_SyncActiveUserinfo();
	CL_CSQC_SyncServerEnable();
	CL_CSQC_WriteStatusSnapshot("world-loaded");
}

qbool CL_CSQC_ExtensionEnabled(void)
{
	return cl_csqc_cvar.integer != 0;
}

qbool CL_CSQC_IsActive(void)
{
	return cl_csqc.transport_enabled && cl_csqc.world_loaded;
}

static qbool CL_CSQC_IsKtxServer(void)
{
	const char* ktxmode = Info_ValueForKey(cl.serverinfo, "ktxmode");
	const char* ktxver = Info_ValueForKey(cl.serverinfo, "ktxver");

	if (!strcasecmp(cls.gamedirfile, "ktx")) {
		return true;
	}

	// KTX servers may expose KTX markers in serverinfo while using base gamedir names.
	if ((ktxmode && ktxmode[0]) || (ktxver && ktxver[0])) {
		return true;
	}

	return false;
}

static qbool CL_CSQC_AllowUnsizedEntityDecode(void)
{
	if (cl_csqc_allow_unsized_nonktx_cvar.integer) {
		return true;
	}

	return CL_CSQC_IsKtxServer();
}

static qbool CL_CSQC_ReadEntityHeader(int packet_end, int* entnum, qbool* remove)
{
	int entword;
	qbool replacement_indexing = (cls.fteprotocolextensions2 & FTE_PEXT2_REPLACEMENTDELTAS) != 0;

	if (!CL_CSQC_RequireBytes(packet_end, 2, "entity header")) {
		return false;
	}

	entword = (unsigned short)MSG_ReadShort();
	if (msg_badread) {
		CL_CSQC_DropCurrentMessage("entity header read");
		return false;
	}

	*remove = (entword & 0x8000) != 0;
	if (replacement_indexing) {
		*entnum = entword & 0x3fff;
		if (entword & 0x4000) {
			if (!CL_CSQC_RequireBytes(packet_end, 1, "entity header ext")) {
				return false;
			}
			*entnum |= MSG_ReadByte() << 14;
		}
	}
	else {
		*entnum = entword & 0x7fff;
	}

	return true;
}

qbool CL_CSQC_ParseEntities(qbool sized)
{
	int packet_start = MSG_GetReadCount();
	int packet_end = -1;
	int packet_size;
	qbool non_ktx_unsized_decode = false;
	qbool replacement_indexing = (cls.fteprotocolextensions2 & FTE_PEXT2_REPLACEMENTDELTAS) != 0;

	cl_csqc.parsed_entity_packets++;
	if (sized) {
		cl_csqc.parsed_sized_entity_packets++;
	}

	if (sized) {
		packet_size = (unsigned short)MSG_ReadShort();
		if (msg_badread) {
			CL_CSQC_DropCurrentMessage("csqcentities size header");
			return true;
		}
		packet_start = MSG_GetReadCount();
		packet_end = packet_start + packet_size;
		if (packet_end > net_message.cursize) {
			CL_CSQC_DropCurrentMessage("csqcentities size overflow");
			return true;
		}
	}
	else if (!CL_CSQC_AllowUnsizedEntityDecode()) {
		if (!cl_csqc.unsized_entities_warned_nonktx) {
			cl_csqc.unsized_entities_warned_nonktx = true;
			CL_CSQC_DropCurrentMessage("unsized csqcentities unsupported for non-ktx server");
		}
		else {
			cl_csqc.dropped_packets++;
			msg_badread = false;
			msg_readcount = net_message.cursize;
		}
		CL_CSQC_WriteStatusSnapshot("entities-unsized-dropped-non-ktx");
		return true;
	}
	else if (!CL_CSQC_IsKtxServer()) {
		non_ktx_unsized_decode = true;
	}

	while (1) {
		int entnum;
		qbool remove;
		byte ent_type;
		qbool store;

		if (sized && MSG_GetReadCount() >= packet_end) {
			break;
		}

		if (!CL_CSQC_ReadEntityHeader(packet_end, &entnum, &remove)) {
			return true;
		}

		if (!remove && entnum == 0) {
			break;
		}

		if (remove) {
			if (replacement_indexing && entnum == 0) {
				memset(cl_csqc_entities, 0, sizeof(cl_csqc_entities));
				cl_csqc.weapon_entnum = -1;
				memset(&cl_csqc.weapon_state, 0, sizeof(cl_csqc.weapon_state));
				continue;
			}
			cl_csqc.parsed_entity_removes++;
			if (entnum > 0 && entnum < CL_MAX_EDICTS) {
				memset(&cl_csqc_entities[entnum], 0, sizeof(cl_csqc_entities[entnum]));
				if (cl_csqc.weapon_entnum == entnum) {
					cl_csqc.weapon_entnum = -1;
					memset(&cl_csqc.weapon_state, 0, sizeof(cl_csqc.weapon_state));
				}
			}
			continue;
		}

		if (!CL_CSQC_RequireBytes(packet_end, 1, "entity type")) {
			return true;
		}
		ent_type = MSG_ReadByte();
		if (msg_badread) {
			CL_CSQC_DropCurrentMessage("entity type read");
			return true;
		}

		store = (entnum > 0 && entnum < CL_MAX_EDICTS);

		if (non_ktx_unsized_decode) {
			if (!CL_CSQC_ParseFteSampleEntityPayload(store ? &cl_csqc_entities[entnum] : &cl_csqc_entities[0], store, ent_type, packet_end)) {
				return true;
			}
		}
		else {
			if (store) {
				cl_csqc_entities[entnum].present = true;
				cl_csqc_entities[entnum].type = ent_type;
			}

			switch (ent_type) {
			case EZCSQC_PROJECTILE:
				if (!CL_CSQC_ParseProjectilePayload(store ? &cl_csqc_entities[entnum] : &cl_csqc_entities[0], store, packet_end)) {
					return true;
				}
				break;
			case EZCSQC_WEAPONINFO:
				if (!CL_CSQC_ParseWeaponInfoPayload(entnum, packet_end)) {
					return true;
				}
				if (store) {
					cl_csqc_entities[entnum].type = ent_type;
				}
				break;
			case EZCSQC_WEAPONDEF:
				if (!CL_CSQC_ParseWeaponDefPayload(packet_end)) {
					return true;
				}
				if (store) {
					cl_csqc_entities[entnum].type = ent_type;
				}
				break;
			default:
				if (sized) {
					cl_csqc.dropped_unknown_entity_sized++;
					Com_Printf("CSQC: unknown entity type %d in sized packet, skipping packet payload\n", ent_type);
					msg_readcount = packet_end;
					return true;
				}
				cl_csqc.dropped_unknown_entity_unsized++;
				CL_CSQC_DropCurrentMessage("unknown unsized entity type");
				return true;
			}
		}

		cl_csqc.parsed_entity_updates++;
	}

	if (sized && packet_end >= 0) {
		if (MSG_GetReadCount() < packet_end) {
			MSG_ReadSkip(packet_end - MSG_GetReadCount());
		}
		if (msg_badread) {
			CL_CSQC_DropCurrentMessage("sized packet skip");
			return true;
		}
		if (MSG_GetReadCount() > packet_end) {
			CL_CSQC_DropCurrentMessage("sized packet overread");
			return true;
		}
	}

	return true;
}

qbool CL_CSQC_ParseGamePacket(qbool sized)
{
	if (!(cls.fteprotocolextensions & FTE_PEXT_CSQC)) {
		return false;
	}

	if (sized) {
		int packet_size = (unsigned short)MSG_ReadShort();
		if (msg_badread) {
			CL_CSQC_DropCurrentMessage("cgamepacket size header");
			return true;
		}
		if (!CL_CSQC_RequireBytes(-1, packet_size, "cgamepacket sized payload")) {
			return true;
		}
		MSG_ReadSkip(packet_size);
		if (msg_badread) {
			CL_CSQC_DropCurrentMessage("cgamepacket sized payload");
			return true;
		}
		cl_csqc.parsed_cgame_packets++;
		CL_CSQC_WriteStatusSnapshot("cgamepacket-sized");
		return true;
	}

	// Unsized cgamepacket is VM-defined and cannot be decoded safely here.
	// Drop the remainder of this network message to avoid parser desync.
	if (!cl_csqc.cgamepacket_warned) {
		cl_csqc.cgamepacket_warned = true;
		Com_Printf("CSQC: dropped unsupported unsized cgamepacket payload\n");
	}
	cl_csqc.dropped_unsized_cgame_packets++;
	msg_readcount = net_message.cursize;
	CL_CSQC_WriteStatusSnapshot("cgamepacket-unsized-dropped");
	return true;
}

static void CL_CSQC_LinkProjectileEntity(int entnum, const cl_csqc_entity_t* src)
{
	entity_t ent;
	struct model_s* model;
	float delta;

	if (src->modelindex <= 0 || src->modelindex >= MAX_MODELS) {
		return;
	}

	model = cl.model_precache[src->modelindex];
	if (!model) {
		return;
	}

	memset(&ent, 0, sizeof(ent));
	ent.model = model;
	ent.colormap = vid.colormap;
	ent.alpha = 1.0f;
	ent.effects = src->effects;
	ent.renderfx = RF_NOSHADOW;

	delta = (float)(cl.time - src->s_time);
	if (delta < 0) {
		delta = 0;
	}

	VectorMA(src->s_origin, delta, src->velocity, ent.origin);
	VectorCopy(src->angles, ent.angles);

	if (src->modelindex == cl_modelindices[mi_rocket] && r_rocketlight.value > 0) {
		CL_NewDlight(entnum, ent.origin, 200, 0.1f, lt_default, false);
	}

	CL_AddEntity(&ent);
}

void CL_CSQC_LinkEntities(void)
{
	int i;

	if (!CL_CSQC_IsActive()) {
		return;
	}

	for (i = 1; i < CL_MAX_EDICTS; ++i) {
		const cl_csqc_entity_t* entity = &cl_csqc_entities[i];
		if (!entity->present) {
			continue;
		}

		if (entity->type == EZCSQC_PROJECTILE) {
			CL_CSQC_LinkProjectileEntity(i, entity);
		}
	}
}

qbool CL_CSQC_GetViewModelState(int* modelindex, int* frame)
{
	int idx;

	if (!modelindex || !frame) {
		return false;
	}

	if (!CL_CSQC_IsActive() || !cl_csqc.weapon_state.present) {
		return false;
	}

	idx = CL_CSQC_MapWeaponToModelIndex(cl_csqc.weapon_state.weapon);
	if (idx <= 0 || idx >= MAX_MODELS || !cl.model_precache[idx]) {
		return false;
	}

	*modelindex = idx;
	*frame = max(0, cl_csqc.weapon_state.frame);
	return true;
}

void CL_CSQC_InputFrame(const usercmd_t* cmd)
{
	if (!cmd) {
		return;
	}

	CL_CSQC_SyncServerEnable();

	cl_csqc.last_input_cmd = *cmd;
	cl_csqc.have_input_cmd = true;
}
