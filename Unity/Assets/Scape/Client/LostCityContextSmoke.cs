using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    IEnumerator ContextSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs()){if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);if(arg.StartsWith("--scape-input-file="))inputFile=arg.Substring(19);}
        contextInputTrace=true;
        username="unitycx"+Guid.NewGuid().ToString("N").Substring(0,4);StartCoroutine(Join());
        yield return AwaitState(()=>state!=null&&state.sidebar?.node!=null,45,"context_login");
        yield return AwaitState(()=>chunks.Count>=49&&!terrainBusy,100,"context_world_ready");
        if(smokeFailed){Application.Quit(1);yield break;}
        yield return TestTab(3);
        var bucket=FindItem(1925);yield return AwaitState(()=>bucket!=null,1,"context_bucket_available");
        if(bucket!=null){
            RequestInput("context-first-item","right",itemHitRects[bucket.component+":"+bucket.slot].center);
            yield return AwaitState(()=>menuOpen&&menu.Exists(m=>m.label=="Drop "+bucket.name),5,"context_first_item_menu");
            var sword=FindItem(1277);if(sword!=null){
                RequestInput("context-replacement-item","right",itemHitRects[sword.component+":"+sword.slot].center);
                yield return AwaitState(()=>menuOpen&&menu.Exists(m=>m.label=="Wield "+sword.name)&&!menu.Exists(m=>m.label=="Drop "+bucket.name),5,"context_item_menu_replaced");
            }
            yield return ClickItemMenu(bucket,"Drop","context-inventory-drop");yield return AwaitState(()=>FindItem(1925)==null,8,"context_inventory_drop_confirmed");}
        if(!smokeFailed)yield return ShopWindowSmoke();
        if(!smokeFailed){
            yield return TestTab(6);yield return AwaitState(()=>menuHitRects.ContainsKey(1152),5,"context_spell_visible");
            RequestInput("context-spell-menu","right",menuHitRects[1152].center);
            yield return AwaitState(()=>menuOpen&&menu.Exists(m=>string.Equals(m.label,"Cast Wind Strike",StringComparison.OrdinalIgnoreCase)),5,"context_spell_cast_option");yield return CapturePlay("-spell-menu");
            yield return AwaitState(()=>selectedSpell==null,1,"context_right_click_does_not_cast");
            int row=menu.FindIndex(m=>string.Equals(m.label,"Cast Wind Strike",StringComparison.OrdinalIgnoreCase));
            if(row>=0){RequestInput("context-spell-select","left",new Vector2(menuRect.x+130,menuRect.y+27+row*24+12));yield return AwaitState(()=>selectedSpell?.id==1152&&!menuOpen,5,"context_spell_selected");}
        }
        Debug.Log("SCAPE_CONTEXT_"+(smokeFailed?"FAILED":"PASSED"));yield return Logout();Application.Quit(smokeFailed?1:0);
    }
}
}
