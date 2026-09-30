using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] class ServerError {public string error,code;}
    bool connectionLoopActive,connectionPaused,disconnecting,everConnected,sessionExpired,unconfirmedAction;
    int connectionGeneration,sessionEpoch,successfulStatePolls;
    sealed class RequestOutcome {public bool transient;public string problem;}
    string FriendlyError(long code,string body){
        string reason=null;try{reason=JsonUtility.FromJson<ServerError>(body)?.error;}catch{}
        if(code==401)return "Your session has ended.";
        if(code==0)return "Cannot reach Lost City. Check the server or connection.";
        if(code>=500)return "Lost City is temporarily unavailable.";
        if(code==429||reason=="Native session limit reached")return "The server is busy. Please try again shortly.";
        if(reason=="Character is already logged in")return "Your previous session is still closing. Please wait.";
        if(reason!=null&&reason.StartsWith("Use a local test name"))return "Use a name beginning with unity, up to 12 letters, numbers or underscores.";
        if(code==403)return "This connection is not permitted by the server.";
        return "That request could not be completed. Please try again.";
    }
    void ClearSessionView(){
        actions.Clear();selectedItem=null;selectedSpell=null;selectedComponent=selectedSlot=-1;countInput="";designGender=-1;lastServerTab=-1;
        state=null;lastServerStateJson=null;movementClock=new LostCityMovementClock();ClearDyingActors();ClearDialogueHead();ResetFeedback();ResetMedia();foreach(var entity in entities.Values)Destroy(entity);entities.Clear();ClearChunks();cameraPlaced=false;
    }
    IEnumerator Request(string path,string method,string body,System.Action<string> done,RequestOutcome outcome=null){
        var reply=outcome??new RequestOutcome();
        int epoch=sessionEpoch;string sentToken=token;
        using(var req=new UnityWebRequest(endpoint+path,method)){
            req.downloadHandler=new DownloadHandlerBuffer();req.timeout=10;
            if(body!=null){req.uploadHandler=new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));req.SetRequestHeader("Content-Type","application/json");}
            if(sentToken!=null)req.SetRequestHeader("Authorization","Bearer "+sentToken);
            yield return req.SendWebRequest();
            // A reply from an abandoned session must never clear or update a newer one.
            if(epoch!=sessionEpoch){
                if(path=="/v1/session"&&method=="POST"&&req.result==UnityWebRequest.Result.Success){
                    string abandoned=null;try{abandoned=JsonUtility.FromJson<Session>(req.downloadHandler.text)?.token;}catch{}
                    if(!string.IsNullOrEmpty(abandoned)&&abandoned!=token){using(var cleanup=new UnityWebRequest(endpoint+"/v1/session","DELETE")){cleanup.downloadHandler=new DownloadHandlerBuffer();cleanup.timeout=10;cleanup.SetRequestHeader("Authorization","Bearer "+abandoned);yield return cleanup.SendWebRequest();}}
                }
                done?.Invoke(null);yield break;
            }
            reply.transient=false;reply.problem=null;
            if(req.result!=UnityWebRequest.Result.Success){
                reply.problem=FriendlyError(req.responseCode,req.downloadHandler.text);
                reply.transient=req.responseCode==0||req.responseCode>=500||req.responseCode==429||reply.problem.StartsWith("Your previous session")||reply.problem.StartsWith("The server is busy");
                Debug.LogWarning("SCAPE_CONNECTION_FAILURE method="+method+" path="+path+" status="+req.responseCode);
                if(req.responseCode==401&&method!="DELETE"&&sentToken!=null&&token==sentToken){
                    token=null;sessionEpoch++;sessionExpired=true;connectionPaused=true;ClearSessionView();status="Session ended. Reconnecting…";
                }else if(reply.transient&&method!="DELETE"){
                    connectionPaused=true;actions.Clear();status=reply.problem;if(path=="/v1/action")unconfirmedAction=true;
                }else if(!disconnecting){if(path=="/v1/session")status=reply.problem;else SetNotice(reply.problem);}
                done?.Invoke(null);
            }else if(req.downloadHandler.data.Length>16000000){reply.problem="The server sent an invalid response. Please reconnect.";done?.Invoke(null);}
            else done?.Invoke(req.downloadHandler.text);
        }
    }
    IEnumerator Join(){
        if(connectionLoopActive||disconnecting)yield break;
        connectionLoopActive=true;connectionPaused=true;joining=true;sessionEpoch++;int generation=++connectionGeneration,attempt=0;
        while(generation==connectionGeneration){
            if(token==null){
                sessionExpired=false;bool valid=false;var outcome=new RequestOutcome();status=everConnected?"Reconnecting to Lost City…":"Connecting to Lost City…";
                yield return Request("/v1/session","POST",JsonUtility.ToJson(new Login{username=username,startLumbridge=!everConnected}),text=>{
                    if(text==null)return;
                    try{var s=JsonUtility.FromJson<Session>(text);if(s.revision!=274||string.IsNullOrEmpty(s.token))throw new Exception();token=s.token;valid=true;}
                    catch{outcome.transient=false;outcome.problem="The server sent an invalid session. Please reconnect.";}
                },outcome);
                if(generation!=connectionGeneration)yield break;
                if(!valid){
                    if(!outcome.transient||++attempt>=5){status=(outcome.problem??"Unable to connect.")+" Select Reconnect to try again.";break;}
                    float delay=Mathf.Min(16,Mathf.Pow(2,attempt));status=(outcome.problem??"Connection lost.")+" Retrying in "+delay+" seconds…";
                    yield return new WaitForSecondsRealtime(delay);continue;
                }
            }
            joining=false;yield return Poll();
            if(generation!=connectionGeneration)yield break;
            if(!sessionExpired)break;
            if(successfulStatePolls>=3)attempt=0;
            if(++attempt>=5){status="Unable to restore your session. Select Reconnect to try again.";break;}
            joining=true;status="Session ended. Reconnecting…";yield return new WaitForSecondsRealtime(Mathf.Min(16,Mathf.Pow(2,attempt)));
        }
        if(generation==connectionGeneration){connectionLoopActive=false;joining=false;connectionPaused=true;}
    }
    IEnumerator Poll(){
        int generation=connectionGeneration,epoch=sessionEpoch,failures=0;successfulStatePolls=0;
        while(token!=null&&generation==connectionGeneration&&epoch==sessionEpoch&&!disconnecting){
            while(actions.Count>0&&!connectionPaused){var a=actions.Dequeue();yield return Request("/v1/action","POST",JsonUtility.ToJson(a),null);if(generation!=connectionGeneration||epoch!=sessionEpoch||token==null||disconnecting)yield break;}
            bool received=false;var outcome=new RequestOutcome();
            yield return Request("/v1/state","GET",null,text=>{
                if(text==null)return;
                try{var next=JsonUtility.FromJson<State>(text);if(next.revision!=274)throw new Exception();if(next.pending){received=true;return;}if(next.player==null)throw new Exception();state=next;lastServerStateJson=text;Apply(next);received=true;connectionPaused=false;everConnected=true;successfulStatePolls++;if(unconfirmedAction){SetNotice("Reconnected. Your last action was not confirmed; check the result before trying again.");unconfirmedAction=false;}status="Connected · revision 274 · tick "+next.tick+(next.busy?" · Performing action…":"");}
                catch{outcome.problem="The server sent invalid game data. Please reconnect.";outcome.transient=false;}
            },outcome);
            if(generation!=connectionGeneration||epoch!=sessionEpoch||token==null||disconnecting)yield break;
            if(!received){
                connectionPaused=true;actions.Clear();
                if(!outcome.transient||++failures>=5){status=(outcome.problem??"Connection lost.")+" Select Reconnect to try again.";yield break;}
                float delay=Mathf.Min(16,Mathf.Pow(2,failures));status=(outcome.problem??"Connection lost.")+" Retrying in "+delay+" seconds…";yield return new WaitForSecondsRealtime(delay);
            }else{failures=0;yield return new WaitForSecondsRealtime(.1f);}
        }
    }
    IEnumerator Logout(){
        if(disconnecting)yield break;
        disconnecting=true;connectionGeneration++;sessionEpoch++;connectionLoopActive=false;joining=false;connectionPaused=true;status="Disconnecting…";
        ClearSessionView();if(token!=null)yield return Request("/v1/session","DELETE",null,null);
        token=null;sessionEpoch++;everConnected=false;sessionExpired=false;unconfirmedAction=false;disconnecting=false;connectionPaused=false;status="Disconnected";
    }
}
}
