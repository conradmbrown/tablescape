using UnityEngine;
namespace Scape.Client {
    public sealed class LostCityCatalogue : ScriptableObject {
        public int[] ids;
        public GameObject[] models;
        public Scape.Assets.LostCityModelAsset[] modelMetadata;
        public Texture2D[] textures;
    }
}
