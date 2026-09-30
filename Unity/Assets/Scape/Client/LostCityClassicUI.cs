using System;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    GUISkin classicSkin;GUIStyle classicMenuItem,classicMenuHover,classicMenuHeader,dialogueText,dialogueButton;Vector2 chatScroll,modalScroll;
    Rect ChatRect=>new Rect(12,Screen.height-181,Mathf.Min(760,Screen.width-388),178);
    Rect MainRect=>HasOriginalOverlay?OriginalOverlayRect:new Rect(260,90,Mathf.Min(690,Screen.width-650),Mathf.Min(550,Screen.height-320));
    static Texture2D Solid(Color c){var t=new Texture2D(1,1);t.SetPixel(0,0,c);t.Apply();return t;}
    static void FillRect(Rect r,Color color){var previous=GUI.color;GUI.color=color;GUI.DrawTexture(r,Texture2D.whiteTexture);GUI.color=previous;}
    void ApplyClassicSkin(){
        if(!classicSkin){classicSkin=Instantiate(GUI.skin);var brown=Solid(new Color32(68,60,48,255));var dark=Solid(new Color32(39,35,29,255));var highlight=Solid(new Color32(91,78,55,255));
            classicSkin.box.normal.background=brown;classicSkin.box.border=new RectOffset(2,2,2,2);classicSkin.box.padding=new RectOffset(10,10,8,8);
            classicSkin.label.normal.textColor=new Color32(255,230,150,255);classicSkin.label.fontSize=14;classicSkin.label.wordWrap=true;
            classicSkin.button.normal.background=dark;classicSkin.button.hover.background=highlight;classicSkin.button.active.background=brown;classicSkin.button.normal.textColor=new Color32(255,220,110,255);classicSkin.button.hover.textColor=Color.yellow;classicSkin.button.fontSize=13;classicSkin.button.wordWrap=true;classicSkin.button.padding=new RectOffset(5,5,5,5);
            classicMenuItem=new GUIStyle(classicSkin.label){alignment=TextAnchor.MiddleLeft,fontSize=15,padding=new RectOffset(4,4,0,0),wordWrap=false};classicMenuItem.normal.textColor=Color.white;classicMenuHover=new GUIStyle(classicMenuItem);classicMenuHover.normal.textColor=Color.yellow;classicMenuHeader=new GUIStyle(classicMenuItem);classicMenuHeader.normal.textColor=new Color32(180,170,140,255);
            dialogueText=new GUIStyle(classicSkin.label){fontSize=16,alignment=TextAnchor.MiddleCenter};dialogueText.normal.textColor=new Color32(35,25,18,255);
            dialogueButton=new GUIStyle(classicMenuItem){alignment=TextAnchor.MiddleCenter,wordWrap=true};dialogueButton.normal.textColor=new Color32(25,45,140,255);dialogueButton.hover.textColor=Color.blue;
        }GUI.skin=classicSkin;
    }
    bool PointerOverInterface(){Vector2 p=new Vector2(Input.mousePosition.x,Screen.height-Input.mousePosition.y);return p.x>=Screen.width-370||MapRect.Contains(p)||ChatRect.Contains(p)||(state!=null&&state.mainRoot>=0&&MainRect.Contains(p));}
    void MirrorScenery(GameObject child){var filter=child.GetComponent<MeshFilter>();var clone=Instantiate(filter.sharedMesh);var vertices=clone.vertices;for(int i=0;i<vertices.Length;i++)vertices[i].z=-vertices[i].z;clone.vertices=vertices;
        for(int sub=0;sub<clone.subMeshCount;sub++){var triangles=clone.GetTriangles(sub);for(int i=0;i<triangles.Length;i+=3){int t=triangles[i];triangles[i]=triangles[i+2];triangles[i+2]=t;}clone.SetTriangles(triangles,sub);}clone.RecalculateNormals();clone.RecalculateBounds();var owner=child.GetComponent<LostCityOwnedMesh>()??child.AddComponent<LostCityOwnedMesh>();if(owner.mesh)Destroy(owner.mesh);owner.mesh=clone;filter.sharedMesh=clone;
    }
    void DrawWidget(Widget w,bool dialogue){if(w.button>0){string label=Plain(!string.IsNullOrWhiteSpace(w.text)?w.text:!string.IsNullOrWhiteSpace(w.option)?w.option:w.action);if(string.IsNullOrWhiteSpace(label))label=w.button==6?"Click here to continue":"Select";if(GUILayout.Button(label,dialogue?dialogueButton:GUI.skin.button,GUILayout.MinHeight(25)))WidgetButton(w);if(dialogue&&Event.current.type==EventType.Repaint)dialogueButtonScreen=GUIUtility.GUIToScreenPoint(GUILayoutUtility.GetLastRect().center);}else if(!string.IsNullOrWhiteSpace(w.text))GUILayout.Label(Plain(w.text),dialogue?dialogueText:GUI.skin.label);}
    void DrawChatPanel(){if(state==null)return;var rect=ChatRect;FillRect(new Rect(rect.x-3,rect.y-3,rect.width+6,rect.height+6),new Color32(49,42,32,255));FillRect(rect,new Color32(202,190,157,255));float portraitWidth=DrawDialogueHead(rect);bool playerHead=state.dialogueHead?.kind=="player";GUILayout.BeginArea(new Rect(rect.x+12+(playerHead?0:portraitWidth),rect.y+6,rect.width-24-portraitWidth,rect.height-12));
        chatScroll=GUILayout.BeginScrollView(chatScroll);
        if(state.chatRoot>=0){dialogueDraws++;foreach(var w in state.ui??Array.Empty<Widget>())if(w.root==state.chatRoot)DrawWidget(w,true);}
        else{var messages=state.messages??Array.Empty<string>();for(int i=Math.Max(0,messages.Length-6);i<messages.Length;i++)GUILayout.Label(Plain(messages[i]),dialogueText);}
        GUILayout.EndScrollView();GUILayout.EndArea();
    }
    void DrawMainModal(){if(state==null||state.mainRoot<0)return;if(DrawOriginalOverlay())return;GUILayout.BeginArea(MainRect,GUI.skin.box);GUILayout.BeginHorizontal();GUILayout.Label("Interface");if(GUILayout.Button("Close",GUILayout.Width(65)))Send(new Action{kind="close"});GUILayout.EndHorizontal();modalScroll=GUILayout.BeginScrollView(modalScroll);foreach(var w in state.ui??Array.Empty<Widget>())if(w.root==state.mainRoot)DrawWidget(w,false);
        DrawInventory(state.mainRoot);
        GUILayout.EndScrollView();GUILayout.EndArea();
    }
}
}
