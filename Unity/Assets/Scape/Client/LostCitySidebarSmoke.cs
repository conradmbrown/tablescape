using System;
using System.Collections;
using System.IO;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    int sidebarTestStep;
    IEnumerator TestTab(int tab){RequestInput("tab-"+tab+"-"+(sidebarTestStep++),"left",SideScreen(TabRect(tab)).center);yield return AwaitState(()=>activeTab==tab&&state.sidebar?.root==state.tabs[tab],10,"icon_tab_"+tab);yield return new WaitForSeconds(.5f);}
    bool AllMenuSprites(SideNode node){if(node==null)return false;bool ok=true;if(!string.IsNullOrEmpty(node.graphic))ok&=MenuIcon(node.graphic)!=null;foreach(var child in node.children??Array.Empty<SideNode>())ok&=AllMenuSprites(child);return ok;}
    IEnumerator SidebarSmoke(){
        foreach(var arg in Environment.GetCommandLineArgs()){if(arg.StartsWith("--scape-test-user="))username=arg.Substring(18);if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);if(arg.StartsWith("--scape-input-file="))inputFile=arg.Substring(19);}
        StartCoroutine(Join());yield return AwaitState(()=>state!=null&&state.sidebar?.node!=null,45,"sidebar_login");if(smokeFailed){Application.Quit(1);yield break;}yield return AwaitState(()=>chunks.Count>=9&&sideDraws>2,60,"sidebar_native_draw");
        yield return AwaitState(()=>MenuIcon("backhmid1-0").width==249&&MenuIcon("backhmid1-0").height==45&&MenuIcon("invback-0").width==190&&MenuIcon("invback-0").height==261&&MenuIcon("backvmid2-0").height==133&&MenuIcon("backhmid2-0")!=null,5,"original_menu_texture_dimensions");
        foreach(int tab in new[]{0,1,2,3,4,5,6,8,9,10,11,12,13}){yield return TestTab(tab);yield return AwaitState(()=>AllMenuSprites(state.sidebar.node)&&missingMenuIcons==0,5,"tab_artwork_"+tab);yield return CapturePlay("-tab-"+tab);File.WriteAllText(captureBase+"-tab-"+tab+".json",JsonUtility.ToJson(state.sidebar,true));}
        yield return TestTab(5);yield return AwaitState(()=>menuHitRects.ContainsKey(5609),5,"prayer_icon_target");RequestInput("prayer-on","left",menuHitRects[5609].center);yield return AwaitState(()=>Array.Exists(state.ui,w=>w.id==5609&&w.active),8,"prayer_icon_active");yield return CapturePlay("-prayer-active");RequestInput("prayer-off","left",menuHitRects[5609].center);yield return AwaitState(()=>Array.Exists(state.ui,w=>w.id==5609&&!w.active),8,"prayer_icon_inactive");
        yield return TestTab(6);RequestInput("spell-hover","move",menuHitRects[1152].center);yield return new WaitForSeconds(1);yield return AwaitState(()=>sideHover>=0,5,"spell_original_tooltip");yield return CapturePlay("-spell-tooltip");RequestInput("spell-select","left",menuHitRects[1152].center);yield return AwaitState(()=>selectedSpell?.id==1152,5,"spell_icon_selection");int xp=state.experience[6];var man=SkillTarget(new SkillStep{target="npc",name="Man",operation="Attack"});if(man!=null)Target("npc",man,1);yield return AwaitState(()=>state.experience[6]>xp,25,"icon_selected_spell_cast");Send(new Action{kind="move",x=(int)state.player.x-10,z=(int)state.player.z-8});yield return new WaitForSeconds(15);
        yield return TestTab(3);var sword=FindItem(1277);if(sword!=null){RequestInput("sword-equip","left",itemHitRects[sword.component+":"+sword.slot].center);yield return AwaitState(()=>Array.Exists(state.inventory,i=>i.id==1277&&i.component==1688),8,"inventory_icon_equip");}
        yield return TestTab(4);yield return CapturePlay("-equipment-worn");var worn=Array.Find(state.inventory,i=>i.id==1277&&i.component==1688);if(worn!=null){RequestInput("sword-remove","left",itemHitRects[worn.component+":"+worn.slot].center);yield return AwaitState(()=>FindItem(1277)!=null,8,"equipment_icon_remove");}
        yield return TestTab(3);var bucket=FindItem(1925);if(bucket!=null){RequestInput("inventory-menu","right",itemHitRects[bucket.component+":"+bucket.slot].center);yield return AwaitState(()=>menuOpen&&menu.Exists(m=>m.label=="Drop Bucket"||m.label=="Drop bucket"),5,"inventory_icon_context_menu");yield return CapturePlay("-inventory-menu");int row=menu.FindIndex(m=>m.label.StartsWith("Drop "));if(row>=0){RequestInput("inventory-drop","left",new Vector2(menuRect.x+130,menuRect.y+27+row*24+12));yield return AwaitState(()=>FindItem(1925)==null,8,"inventory_icon_drop");}}
        if(!smokeFailed)yield return ShopWindowSmoke();
        File.WriteAllText(captureBase+"-metrics.json",$"{{\"passed\":{(!smokeFailed).ToString().ToLowerInvariant()},\"tabs\":13,\"missingIcons\":{missingMenuIcons},\"sidebarDraws\":{sideDraws},\"iconDraws\":{iconsDrawn}}}");Debug.Log("SCAPE_SIDEBAR_"+(smokeFailed?"FAILED":"PASSED"));yield return Logout();Application.Quit(smokeFailed?1:0);
    }
    IEnumerator ClickItemMenu(Item item,string operation,string label){
        string key=item.component+":"+item.slot;
        yield return AwaitState(()=>itemHitRects.ContainsKey(key),5,label+"_visible_icon");if(!itemHitRects.ContainsKey(key))yield break;
        RequestInput(label+"-menu","right",itemHitRects[key].center);
        yield return AwaitState(()=>menuOpen&&menu.Exists(m=>m.label==operation+" "+item.name),5,label+"_context_menu");
        yield return CapturePlay("-"+label+"-menu");
        int row=menu.FindIndex(m=>m.label==operation+" "+item.name);if(row<0)yield break;
        RequestInput(label+"-click","left",new Vector2(menuRect.x+130,menuRect.y+27+row*24+12));
    }
    IEnumerator ShopWindowSmoke(){
        Send(new Action{kind="move",x=3214,z=3241});
        yield return AwaitState(()=>Mathf.Abs(state.player.x-3214)<3&&Mathf.Abs(state.player.z-3241)<3,50,"shop_walk");
        var keeper=SkillTarget(new SkillStep{target="npc",name="Shop keeper",operation="Trade"});
        yield return AwaitState(()=>keeper!=null,2,"shop_keeper_available");if(keeper==null)yield break;
        Target("npc",keeper,Array.IndexOf(keeper.ops,"Trade")+1);
        yield return AwaitState(()=>state.mainRoot>=0&&Array.Exists(state.inventory,i=>i.id==1935&&i.root==state.mainRoot),20,"shop_has_jug_stock");
        yield return new WaitForSeconds(1);yield return CapturePlay("-shop-stock");
        var stock=Array.Find(state.inventory,i=>i.id==1935&&i.root==state.mainRoot);if(stock==null)yield break;
        // Fresh ordinary accounts have no coins. Fund the UI test by actually
        // selling a starter sword instead of modifying the player's save.
        if(ItemCount(995)<10){
            var starter=Array.Find(state.inventory,i=>i.id==1277&&Array.Exists(i.buttons??Array.Empty<string>(),b=>b=="Sell 1"));
            yield return AwaitState(()=>starter!=null,1,"shop_starter_sword_available");
            if(starter==null)yield break;
            int before=ItemCount(995);yield return ClickItemMenu(starter,"Sell 1","shop-fund");
            yield return AwaitState(()=>ItemCount(995)>before&&FindItem(1277)==null,10,"shop_starter_sale_funds_purchase");
        }
        int count=ItemCount(1935),coins=ItemCount(995);yield return ClickItemMenu(stock,"Buy 1","shop-buy");
        yield return AwaitState(()=>ItemCount(1935)==count+1&&ItemCount(995)<coins,10,"shop_mouse_purchase");
        var jug=Array.Find(state.inventory,i=>i.id==1935&&Array.Exists(i.buttons??Array.Empty<string>(),b=>b=="Sell 1"));if(jug==null){smokeFailed=true;Debug.LogError("SCAPE_PARITY_FAILED shop_sell_inventory_missing");yield break;}
        yield return ClickItemMenu(jug,"Sell 1","shop-sell");
        yield return AwaitState(()=>ItemCount(1935)==count,10,"shop_mouse_sale");yield return CapturePlay("-shop-after");
        Send(new Action{kind="close"});yield return AwaitState(()=>state.mainRoot<0,8,"shop_close");
    }

}
}
