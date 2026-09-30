using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    sealed class Chunk {public GameObject root;public int x,z,level;public bool interactive;public List<Mesh> meshes=new List<Mesh>();public List<Material> materials=new List<Material>();public List<string> keys=new List<string>();}
    readonly Dictionary<string,Chunk> chunks=new Dictionary<string,Chunk>();
    bool streaming,cameraPlaced;int chunkX,chunkZ,chunkLevel;float smoothYaw=25,smoothPitch=55,smoothDistance=22,yawVelocity,pitchVelocity,distanceVelocity,nextMapRender;Vector3 cameraVelocity;
    Camera mapCamera;RenderTexture mapTexture;Rect MapRect {get {float size=Mathf.Clamp(SideRect.y-100,80,220);return new Rect(Screen.width-185-size/2,72,size,size);}}
    void InitializeMinimap(){mapTexture=new RenderTexture(256,256,16);mapTexture.Create();mapCamera=new GameObject("North-up minimap").AddComponent<Camera>();mapCamera.orthographic=true;mapCamera.orthographicSize=24;mapCamera.nearClipPlane=.1f;mapCamera.farClipPlane=220;mapCamera.clearFlags=CameraClearFlags.SolidColor;mapCamera.backgroundColor=new Color(.06f,.08f,.10f);mapCamera.cullingMask=1<<8;mapCamera.targetTexture=mapTexture;mapCamera.enabled=false;}
    bool MinimapContainsMouse()=>MapRect.Contains(new Vector2(Input.mousePosition.x,Screen.height-Input.mousePosition.y));
    void CameraInput(){
        if(Input.GetKey(KeyCode.LeftArrow))yaw+=80*Time.deltaTime;if(Input.GetKey(KeyCode.RightArrow))yaw-=80*Time.deltaTime;
        if(Input.GetKey(KeyCode.UpArrow))pitch+=50*Time.deltaTime;if(Input.GetKey(KeyCode.DownArrow))pitch-=50*Time.deltaTime;
        if(Input.GetMouseButton(1)&&rightDragging){yaw-=Input.GetAxis("Mouse X")*4;pitch-=Input.GetAxis("Mouse Y")*3;}
        if(!PointerOverInterface())distance-=Input.mouseScrollDelta.y*2;
        pitch=Mathf.Clamp(pitch,20,85);distance=Mathf.Clamp(distance,5,65);
    }
    void LateUpdate(){
        if(slopeTestFocus||state==null||!view||!entities.TryGetValue("player",out var player))return;
        Vector3 follow=player.transform.position+Vector3.up*.6f;
        if(!cameraPlaced||Vector3.Distance(target,follow)>16){target=follow;cameraVelocity=Vector3.zero;smoothYaw=yaw;smoothPitch=pitch;smoothDistance=distance;cameraPlaced=true;}
        target=Vector3.SmoothDamp(target,follow,ref cameraVelocity,.12f);
        smoothYaw=Mathf.SmoothDampAngle(smoothYaw,yaw,ref yawVelocity,.12f);smoothPitch=Mathf.SmoothDamp(smoothPitch,pitch,ref pitchVelocity,.12f);smoothDistance=Mathf.SmoothDamp(smoothDistance,distance,ref distanceVelocity,.15f);
        var rotation=Quaternion.Euler(smoothPitch,smoothYaw,0);view.transform.SetPositionAndRotation(target-rotation*Vector3.forward*smoothDistance,rotation);
        mapCamera.transform.SetPositionAndRotation(player.transform.position+Vector3.up*100,Quaternion.Euler(90,0,0));
        if(Time.unscaledTime>=nextMapRender){mapCamera.Render();nextMapRender=Time.unscaledTime+.1f;}
    }
    void DrawMinimap(){
        if(state==null||!mapTexture)return;var rect=MapRect;GUI.Box(new Rect(rect.x-3,rect.y-3,rect.width+6,rect.height+6),"");GUI.DrawTexture(rect,mapTexture);GUI.Label(new Rect(rect.center.x-5,rect.y+3,30,20),"N");
        foreach(var pair in entities){if(pair.Key!="player"&&!pair.Key.StartsWith("npc-")&&!pair.Key.StartsWith("player-"))continue;var v=mapCamera.WorldToViewportPoint(pair.Value.transform.position);if(v.x<0||v.x>1||v.y<0||v.y>1)continue;GUI.color=pair.Key=="player"?Color.white:pair.Key.StartsWith("npc-")?Color.yellow:Color.cyan;GUI.DrawTexture(new Rect(rect.x+v.x*rect.width-2,rect.y+(1-v.y)*rect.height-2,4,4),Texture2D.whiteTexture);}
        GUI.color=Color.white;var e=Event.current;if(e.type==EventType.MouseDown&&e.button==0&&rect.Contains(e.mousePosition)){var p=mapCamera.ViewportToWorldPoint(new Vector3((e.mousePosition.x-rect.x)/rect.width,1-(e.mousePosition.y-rect.y)/rect.height,100));MarkClick(e.mousePosition,false);Send(new Action{kind="move",x=Mathf.FloorToInt(p.x),z=Mathf.FloorToInt(p.z),run=runEnabled});e.Use();}
    }
    int chunkGeneration;
    void SetChunkInteraction(Chunk chunk,bool force=false){bool enabled=chunk.level==chunkLevel;if(chunk.interactive==enabled&&!force)return;foreach(var collider in chunk.root.GetComponentsInChildren<Collider>())collider.enabled=enabled;chunk.interactive=enabled;}
    void UpdateChunkRequests(){chunkX=Mathf.FloorToInt(state.player.x/16)*16;chunkZ=Mathf.FloorToInt(state.player.z/16)*16;chunkLevel=state.level;foreach(var chunk in chunks.Values)SetChunkInteraction(chunk);if(!streaming)StartCoroutine(StreamChunks());}
    IEnumerator StreamChunks(){
        streaming=true;terrainBusy=true;int generation=chunkGeneration;
        while(state!=null&&token!=null&&!connectionPaused&&!disconnecting&&generation==chunkGeneration){
            var remove=new List<string>();foreach(var p in chunks)if(p.Value.level>chunkLevel||Math.Abs(p.Value.x-chunkX)>64||Math.Abs(p.Value.z-chunkZ)>64)remove.Add(p.Key);foreach(var key in remove)RemoveChunk(key);
            int bx=0,bz=0,best=int.MaxValue;string wanted=null;int level=chunkLevel;
            for(int floor=chunkLevel;floor>=0;floor--)for(int dx=-3;dx<=3;dx++)for(int dz=-3;dz<=3;dz++){int x=chunkX+dx*16,z=chunkZ+dz*16;string key=$"{x}:{z}:{floor}";int score=(dx*dx+dz*dz)*4+chunkLevel-floor;if(x>=0&&z>=0&&!chunks.ContainsKey(key)&&score<best){wanted=key;bx=x;bz=z;level=floor;best=score;}}
            if(wanted==null)break;Terrain data=null;yield return Request($"/v1/chunk?x={bx}&z={bz}&level={level}","GET",null,text=>{if(text!=null)data=JsonUtility.FromJson<Terrain>(text);});
            if(state==null||token==null||generation!=chunkGeneration)break;if(data==null)break;if(level>chunkLevel||Math.Abs(bx-chunkX)>64||Math.Abs(bz-chunkZ)>64)continue;
            if(!terrainRoot)terrainRoot=new GameObject("Streamed original terrain");
            var chunk=new Chunk{x=bx,z=bz,level=level,interactive=true,root=new GameObject("Chunk "+wanted)};chunk.root.transform.SetParent(terrainRoot.transform);chunks[wanted]=chunk;
            foreach(var s in data.meshes??Array.Empty<Surface>()){
                var vertices=new Vector3[s.vertices.Length/3];var colours=new Color[vertices.Length];var uv=new Vector2[vertices.Length];var indices=new int[vertices.Length];
                for(int i=0;i<vertices.Length;i++){vertices[i]=new Vector3(s.vertices[i*3],s.vertices[i*3+1],s.vertices[i*3+2]);colours[i]=new Color(s.colours[i*3],s.colours[i*3+1],s.colours[i*3+2]);uv[i]=new Vector2(s.uv[i*2],s.uv[i*2+1]);indices[i]=i;}
                var mesh=new Mesh{indexFormat=UnityEngine.Rendering.IndexFormat.UInt32};mesh.vertices=vertices;mesh.colors=colours;mesh.uv=uv;mesh.triangles=indices;mesh.RecalculateBounds();chunk.meshes.Add(mesh);
                var material=new Material(surfaceShader);if(s.texture>=0&&s.texture<catalogue.textures.Length&&catalogue.textures[s.texture])material.mainTexture=catalogue.textures[s.texture];chunk.materials.Add(material);
                var go=new GameObject("Ground texture "+s.texture);go.layer=8;go.transform.SetParent(chunk.root.transform);go.AddComponent<MeshFilter>().sharedMesh=mesh;go.AddComponent<MeshRenderer>().sharedMaterial=material;go.AddComponent<MeshCollider>().sharedMesh=mesh;
            }
            var alive=new HashSet<string>();int count=0;foreach(var actor in data.locs??Array.Empty<Actor>()){if(state==null||generation!=chunkGeneration)break;string key="static-"+wanted+"/"+actor.key;Show(key,actor,true,alive);entities[key].transform.SetParent(chunk.root.transform,true);chunk.keys.Add(key);if(++count%40==0)yield return null;}
            if(generation==chunkGeneration){AttachDiagonalDecor(chunk);SetChunkInteraction(chunk,true);}
            yield return null;
        }
        if(generation==chunkGeneration){terrainBusy=false;streaming=false;}
    }
    void RemoveChunk(string key){var c=chunks[key];foreach(var k in c.keys){if(entities.TryGetValue(k,out var go))Destroy(go);entities.Remove(k);}foreach(var m in c.meshes)Destroy(m);foreach(var m in c.materials)Destroy(m);Destroy(c.root);chunks.Remove(key);}
    void ClearChunks(){chunkGeneration++;streaming=false;terrainBusy=false;foreach(var key in new List<string>(chunks.Keys))RemoveChunk(key);if(terrainRoot)Destroy(terrainRoot);terrainRoot=null;}
    void OnDestroy(){CloseClientControl();ClearDyingActors();DisposeDialogueHead();if(mapTexture){mapTexture.Release();Destroy(mapTexture);}if(mapCamera)Destroy(mapCamera.gameObject);}
}
}
