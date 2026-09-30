using System;
using System.IO;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEditor.Build.Reporting;
using UnityEngine;
using Scape.Client;
public static class ScapeBuild {
    public static void Build(){
        ScapeAssetVerification.Run();
        Directory.CreateDirectory("Assets/Scape/Generated");
        var catalogue=AssetDatabase.LoadAssetAtPath<LostCityCatalogue>("Assets/Scape/Generated/Catalogue.asset");
        if(!catalogue){catalogue=ScriptableObject.CreateInstance<LostCityCatalogue>();AssetDatabase.CreateAsset(catalogue,"Assets/Scape/Generated/Catalogue.asset");}
        var ids=new List<int>();var models=new List<GameObject>();var metadata=new List<Scape.Assets.LostCityModelAsset>();
        foreach(string file in Directory.GetFiles("Assets/LostCity274/models","*.ob2")){
            Scape.Assets.LostCityModelAsset data=null;foreach(var asset in AssetDatabase.LoadAllAssetsAtPath(file.Replace('\\','/')))if(asset is Scape.Assets.LostCityModelAsset modelData)data=modelData;
            if(!data||data.cornerVertices==null)throw new InvalidDataException("Missing original lighting topology: "+file);metadata.Add(data);
            ids.Add(int.Parse(Path.GetFileNameWithoutExtension(file)));models.Add(AssetDatabase.LoadAssetAtPath<GameObject>(file.Replace('\\','/')));
        }
        catalogue.modelMetadata=metadata.ToArray();catalogue.ids=ids.ToArray();catalogue.models=models.ToArray();catalogue.textures=new Texture2D[50];
        for(int i=0;i<50;i++)catalogue.textures[i]=AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/LostCity274/textures/"+i+".png");
        EditorUtility.SetDirty(catalogue);AssetDatabase.SaveAssets();
        var scene=EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
        var root=new GameObject("Lost City native Unity client");var client=root.AddComponent<LostCityClient>();client.catalogue=catalogue;client.surfaceShader=AssetDatabase.LoadAssetAtPath<Shader>("Assets/Scape/Shaders/CacheSurface.shader");
        EditorSceneManager.SaveScene(scene,"Assets/Scape/Generated/LostCity.unity");
        PlayerSettings.productName="Lost City Tabletop";PlayerSettings.companyName="Scape Tabletop";
        PlayerSettings.defaultScreenWidth=1440;PlayerSettings.defaultScreenHeight=900;PlayerSettings.fullScreenMode=FullScreenMode.Windowed;
        // The private loopback gateway uses HTTP in both release and development players.
        PlayerSettings.insecureHttpOption=InsecureHttpOption.AlwaysAllowed;
        string output=Path.GetFullPath("../Builds/Linux/ScapeClient");var args=Environment.GetCommandLineArgs();for(int i=0;i<args.Length-1;i++)if(args[i]=="-buildOutput")output=args[i+1];
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{"Assets/Scape/Generated/LostCity.unity"},locationPathName=output,target=BuildTarget.StandaloneLinux64,options=BuildOptions.None});
        if(report.summary.result!=BuildResult.Succeeded)throw new Exception("Unity client build failed: "+report.summary.result);
        Debug.Log("SCAPE_UNITY_BUILD_PASSED "+output);
    }
}
