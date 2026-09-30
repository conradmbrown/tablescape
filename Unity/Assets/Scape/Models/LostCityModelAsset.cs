using UnityEngine;
namespace Scape.Assets
{
    // Retain original animation labels and face metadata for the gameplay/animation port.
    public sealed class LostCityModelAsset : ScriptableObject
    {
        public int revision = 274;
        public int[] vertexLabels, faceLabels, priorities, faceColours, renderTypes, faceAlpha;
        public int[] cornerVertices;
        public int sourceVertexCount, sourceFaceCount;
        public Mesh mesh;
    }
}
