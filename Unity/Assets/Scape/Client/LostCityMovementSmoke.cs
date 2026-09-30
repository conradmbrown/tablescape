using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Text;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool MovementTimingChecks(){
        var clock=new LostCityMovementClock();var track=new LostCityMovementTrack();
        int received=-1;Vector3 previous=Vector3.zero;double last=0;float low=float.MaxValue,high=0;
        for(int frame=0;frame<1200;frame++){
            double now=frame/120.0;int next=received+1;
            double jitter=next%3==0?.14:next%3==1?.03:.08;
            if(now>=next*.6+jitter){received=next;clock.Observe(next,now);track.Add(new Vector3(next,0,0),next,false);}
            if(received<0)continue;
            var position=track.Evaluate(clock.At(now));
            if(now>2){float speed=(position.x-previous.x)/(float)(now-last);low=Mathf.Min(low,speed);high=Mathf.Max(high,speed);}
            previous=position;last=now;
        }
        bool good=low>1.6f&&high<1.74f;
        var path=new LostCityMovementTrack();path.Add(Vector3.zero,0,true);path.Add(new Vector3(1,0,1),1,false);path.Evaluate(.5);good&=path.Moving&&!path.Running;
        path.Add(new Vector3(3,0,1),2,false);path.Evaluate(1.5);good&=path.Running;
        var at=path.Evaluate(1.5);path.Add(new Vector3(99,0,99),1,false);good&=path.Evaluate(1.5)==at;
        good&=path.Evaluate(20)==new Vector3(3,0,1)&&!path.Moving;
        good&=path.Add(new Vector3(30,0,30),3,false)&&path.Evaluate(2)==new Vector3(30,0,30);
        Debug.Log("SCAPE_MOVEMENT_TIMING "+good+" jitteredWalkSpeed="+low+".."+high);
        return good;
    }
    IEnumerator MovementSmoke(){
        if(!MovementTimingChecks()){Debug.LogError("SCAPE_MOVEMENT_TIMING_FAILED");Application.Quit(1);yield break;}
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);
        yield return CheckFacingRegression();if(!facingRegression){Application.Quit(1);yield break;}
        username="unitymv"+Guid.NewGuid().ToString("N").Substring(0,4);StartCoroutine(Join());
        yield return AwaitState(()=>state!=null,45,"movement_login");
        yield return AwaitState(()=>chunks.Count>=49&&!terrainBusy,100,"movement_world_ready");
        if(smokeFailed){Application.Quit(1);yield break;}
        distance=12;yield return new WaitForSeconds(2);
        var csv=new StringBuilder("leg,time,tick,serverX,serverZ,x,z,cameraX,cameraZ,sequence,frame\n");
        yield return TraceMovement(csv,"walk",3242,3218,false);
        yield return TraceMovement(csv,"run",3222,3218,true);
        if(captureBase!=null)File.WriteAllText(captureBase+"-motion.csv",csv.ToString());
        Debug.Log(smokeFailed?"SCAPE_MOVEMENT_FAILED":"SCAPE_MOVEMENT_PASSED");
        yield return Logout();Application.Quit(smokeFailed?1:0);
    }
    IEnumerator TraceMovement(StringBuilder csv,string leg,int x,int z,bool run){
        Send(new Action{kind="move",x=x,z=z,run=run});
        var player=entities["player"];var anim=player.GetComponent<LostCityAnimator>();
        float began=Time.realtimeSinceStartup,arrived=-1;bool captured=false;
        while(Time.realtimeSinceStartup-began<35){
            yield return new WaitForEndOfFrame();
            var p=player.transform.position;var c=view.transform.position;float elapsed=Time.realtimeSinceStartup-began;
            csv.AppendFormat(CultureInfo.InvariantCulture,"{0},{1:F6},{2},{3},{4},{5:F6},{6:F6},{7:F6},{8:F6},{9},{10}\n",leg,elapsed,state.tick,state.player.x,state.player.z,p.x,p.z,c.x,c.z,anim.CurrentSequence,anim.CurrentFrame);
            if(!captured&&elapsed>5){captured=true;yield return CapturePlay("-"+leg);}
            bool there=state.player.x==x&&state.player.z==z&&Vector2.Distance(new Vector2(p.x,p.z),new Vector2(x+.5f,z+.5f))<.02f;
            if(there&&arrived<0)arrived=elapsed;if(!there)arrived=-1;
            if(arrived>=0&&elapsed-arrived>1.5f)break;
        }
        yield return AwaitState(()=>state.player.x==x&&state.player.z==z,1,leg+"_server_destination");
        yield return AwaitState(()=>Vector2.Distance(new Vector2(player.transform.position.x,player.transform.position.z),new Vector2(x+.5f,z+.5f))<.02f,2,leg+"_rendered_destination");
    }
}
}
