#include  "MetroMidi.h"
#include "Cowbell.h"
#include "Rim.h"

#define NoteNum_K 2
#define NoteNumx2_K  4 


extern uint32_t *track_point;
// extern uint32_t *Restart_Point;

//=====================================================================================================================//
uint32_t addr_note_K[NoteNum_K];    //架子鼓
uint32_t volumn_note_K[NoteNum_K];  //架子鼓
uint32_t backup_addr_note_K[NoteNumx2_K];
uint32_t point_note_K[NoteNumx2_K];
uint32_t sampleLen_K[NoteNum_K]={6722,6722};//rim,cowbell
extern void	Midi_ParaInit(void);

//=====================================================================================================================//

void DrumInit(void)
{
	int i;
	Midi_ParaInit();
	for(i=0;i<NoteNum_K;i++)
	{
		backup_addr_note_K[i] = 0;
		//volumn_note_K[i] = 0;
		addr_note_K[i] = 0;
	}
} 



float drum_prc_K(void)
{
	int i;
	float tempdataK = 0;
  int j;
	for(i=0;i<NoteNum_K;i++)
	{
	/////////////////////////kick///////////////////////
		if(addr_note_K[i] == 0x01)
		{
			if(backup_addr_note_K[i] == 0x01)
			{
				point_note_K[i] = 0x00;
			}
						
			backup_addr_note_K[i] = 1;
			addr_note_K[i] = 0x00;
		}
		//=============================================
		else if(backup_addr_note_K[i] == 0x01)
		{
			if(point_note_K[i] >= sampleLen_K[i])//sampleLen_K[i])
			{
				point_note_K[i] = 0x00;
				backup_addr_note_K[i]  = 0;
			}
			else
			{				
				
				switch(i)
				{           
					//metro
						case 0:
								 tempdataK += (float)volumn_note_K[i]/100.0f * DRim[point_note_K[i]]*0.00003685f;
					       point_note_K[i]++;
						     break;
							case 1:
								 tempdataK += (float)volumn_note_K[i]/100.0f * DCowbell[point_note_K[i]]*0.00003685f;
					       point_note_K[i]++;
						   break;
//							
					default:break;
				}
			}
		}
	}		

	return(tempdataK);	
}

extern void Midi_Parm(void);
extern void M_Drmdrum_timer(void);
extern void M_DrmMidi_deal(void);
extern unsigned char M_DrmSwith_before;
float Drumer_I2s(int num,int bpm)
{
	int RhyVol;	
	float DrumOutI;
	float DrumVolF,DrumOutF;
	Rhythm_Struct2M.Style=num;
	Rhythm_Struct2M.Switch=1;
	Rhythm_Struct2M.Bmp=bpm;
	//if (Rhythm_Struct2M.Switch == 1)
//	{
    //	Midi_Parm();
			M_Drmdrum_timer();
			M_DrmMidi_deal();	

			//if(DrumMode==1||pre_drum_flg==1)//pre drumer+ hander drum
			{

				DrumOutI=0.7f*drum_prc_K(); //Jiazigu
			}	    
												 
			//鼓
			//Rhythm_Struct.Switch=1;
//			RhyVol=Rhythm_Struct2M.Vol; 
//			
//			DrumVolF=(float)RhyVol*0.05f;
			DrumOutF=0.32f*DrumOutI;//*DrumVolF;
	
//	}
//	else
//	{
//		M_DrmSwith_before = 0;
//		DrumOutF=0;
//	}


	return DrumOutF;
}

