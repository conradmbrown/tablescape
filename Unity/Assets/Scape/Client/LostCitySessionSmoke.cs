using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    IEnumerator SessionSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);
        username="unitycn"+Guid.NewGuid().ToString("N").Substring(0,4);StartCoroutine(Join());
        yield return AwaitState(()=>state!=null&&!connectionPaused,35,"session_login");if(smokeFailed){Application.Quit(1);yield break;}
        yield return AwaitState(()=>chunks.Count>=9,45,"session_rendered");
        Send(new Action{kind="move",x=(int)state.player.x+3,z=(int)state.player.z});yield return AwaitState(()=>state.player.x>=3225,15,"session_move_before_expiry");
        var position=new Vector2(state.player.x,state.player.z);string experience=string.Join(",",state.experience);int itemCount=state.inventory.Length;string oldToken=token;
        selectedItem=state.inventory.Length>0?state.inventory[0]:null;
        yield return Request("/v1/session","DELETE",null,null); // Real server invalidation, not a mocked 401.
        yield return AwaitState(()=>token!=null&&token!=oldToken&&state!=null&&!connectionPaused,45,"session_401_recovered");
        if(smokeFailed){Application.Quit(1);yield break;}
        yield return AwaitState(()=>Vector2.Distance(position,new Vector2(state.player.x,state.player.z))<.01f&&experience==string.Join(",",state.experience)&&itemCount==state.inventory.Length&&selectedItem==null,2,"session_progress_preserved");
        oldToken=token;
        yield return Request("/__test/fault","POST","{\"mode\":\"offline\",\"seconds\":5}",null);
        Send(new Action{kind="move",x=(int)state.player.x+4,z=(int)state.player.z});
        yield return AwaitState(()=>connectionPaused&&actions.Count==0,8,"session_outage_paused_and_queue_cleared");yield return CapturePlay("-reconnecting");
        yield return AwaitState(()=>!connectionPaused&&state!=null,20,"session_outage_recovered");
        yield return AwaitState(()=>token==oldToken&&Vector2.Distance(position,new Vector2(state.player.x,state.player.z))<.01f,2,"session_action_not_replayed");
        yield return Request("/__test/fault","POST","{\"mode\":\"malformed\",\"remaining\":1}",null);
        yield return AwaitState(()=>connectionPaused&&!connectionLoopActive,8,"session_bad_response_stops_cleanly");yield return CapturePlay("-manual-reconnect");
        StartCoroutine(Join());yield return AwaitState(()=>!connectionPaused&&state!=null,12,"session_manual_reconnect");
        yield return Request("/__test/fault","POST","{\"mode\":\"offline\",\"seconds\":120}",null);
        yield return AwaitState(()=>connectionPaused&&!connectionLoopActive,55,"session_retry_limit");
        StartCoroutine(Join());yield return new WaitForSeconds(.5f);yield return Logout();
        yield return Request("/__test/fault","POST","{\"mode\":\"ok\"}",null);yield return new WaitForSecondsRealtime(5);
        yield return AwaitState(()=>token==null&&state==null&&!connectionLoopActive&&!joining&&actions.Count==0&&status=="Disconnected",1,"session_cancel_stays_disconnected");
        yield return Request("/__test/fault","POST","{\"mode\":\"slow_login\",\"seconds\":6}",null);
        StartCoroutine(Join());yield return new WaitForSecondsRealtime(.5f);yield return Logout();yield return new WaitForSecondsRealtime(5);
        yield return AwaitState(()=>token==null&&!connectionLoopActive&&status=="Disconnected",1,"session_late_login_ignored");
        yield return Request("/__test/fault","POST","{\"mode\":\"ok\"}",null);
        StartCoroutine(Join());yield return AwaitState(()=>state!=null&&!connectionPaused,12,"session_cancelled_login_released");yield return Logout();
        Debug.Log("SCAPE_SESSION_"+(smokeFailed?"FAILED":"PASSED"));Application.Quit(smokeFailed?1:0);
    }
}
}
