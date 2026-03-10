#ifndef EZQUAKE_CL_CSQC_H
#define EZQUAKE_CL_CSQC_H

void CL_CSQC_Init(void);
void CL_CSQC_Shutdown(void);
void CL_CSQC_ClearState(void);
void CL_CSQC_ServerInfoChanged(void);
void CL_CSQC_WorldLoaded(void);
qbool CL_CSQC_ExtensionEnabled(void);

qbool CL_CSQC_IsActive(void);
qbool CL_CSQC_ParseEntities(qbool sized);
qbool CL_CSQC_ParseGamePacket(qbool sized);

void CL_CSQC_LinkEntities(void);
qbool CL_CSQC_GetViewModelState(int* modelindex, int* frame);
void CL_CSQC_InputFrame(const usercmd_t* cmd);

#endif
