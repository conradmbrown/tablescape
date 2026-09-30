using UnityEditor;
using UnityEngine;

public sealed class LostCityTextureImporter : AssetPostprocessor
{
    public override uint GetVersion() => 3;
    void OnPostprocessTexture(Texture2D texture)
    {
        if (!assetPath.StartsWith("Assets/LostCity274/textures/", System.StringComparison.Ordinal)) return;
        // Lost City's source PNGs use opaque magenta for cache palette index zero.
        // Preserve the source files; convert that key to alpha in the imported texture.
        var pixels = texture.GetPixels32();
        for (int i = 0; i < pixels.Length; i++)
            if (pixels[i].r == 255 && pixels[i].g == 0 && pixels[i].b == 255) pixels[i] = new Color32(0, 0, 0, 0);
        texture.SetPixels32(pixels);
        texture.Apply(true, false);
    }
    void OnPreprocessTexture()
    {
        if (!assetPath.StartsWith("Assets/LostCity274/textures/", System.StringComparison.Ordinal)) return;
        var texture=(TextureImporter)assetImporter;
        texture.textureType=TextureImporterType.Default;
        texture.textureCompression=TextureImporterCompression.Uncompressed;
        texture.filterMode=FilterMode.Trilinear;
        texture.anisoLevel=4;
        texture.wrapMode=TextureWrapMode.Repeat;
        texture.mipmapEnabled=true;
        var platform=texture.GetDefaultPlatformTextureSettings();
        platform.format=TextureImporterFormat.RGBA32;
        texture.SetPlatformTextureSettings(platform);
        texture.alphaSource=TextureImporterAlphaSource.FromInput;
        texture.sRGBTexture=true;
    }
}
