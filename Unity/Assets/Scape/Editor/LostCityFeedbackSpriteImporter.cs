using UnityEditor;
using UnityEngine;
public sealed class LostCityFeedbackSpriteImporter:AssetPostprocessor {
    public override uint GetVersion()=>2;
    bool Applies=>(assetPath.StartsWith("Assets/Scape/Resources/Feedback/")||assetPath.StartsWith("Assets/Scape/Resources/Overlays/")||assetPath.StartsWith("Assets/Scape/Resources/Icons/"));
    void OnPreprocessTexture(){if(!Applies)return;var t=(TextureImporter)assetImporter;t.textureType=TextureImporterType.Default;t.textureCompression=TextureImporterCompression.Uncompressed;t.filterMode=FilterMode.Point;t.mipmapEnabled=false;t.npotScale=TextureImporterNPOTScale.None;t.wrapMode=TextureWrapMode.Clamp;var p=t.GetDefaultPlatformTextureSettings();p.format=TextureImporterFormat.RGBA32;t.SetPlatformTextureSettings(p);}
    void OnPostprocessTexture(Texture2D texture){if(!Applies)return;var pixels=texture.GetPixels32();for(int i=0;i<pixels.Length;i++)if(pixels[i].r==255&&pixels[i].g==0&&pixels[i].b==255)pixels[i]=new Color32(0,0,0,0);texture.SetPixels32(pixels);texture.Apply(false,false);}
}
