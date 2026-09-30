Shader "Scape/CacheSurface"
{
    Properties { _MainTex ("Original texture", 2D) = "white" {} }
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        Cull Back
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            struct Input { float4 vertex : POSITION; float2 uv : TEXCOORD0; float4 color : COLOR; };
            struct Output { float4 vertex : SV_POSITION; float2 uv : TEXCOORD0; float4 color : COLOR; };
            Output vert(Input v) { Output o; o.vertex=UnityObjectToClipPos(v.vertex); o.uv=v.uv; o.color=v.color; return o; }
            fixed4 frag(Output i) : SV_Target {
                fixed4 texel=tex2D(_MainTex,i.uv);
                // Source RGB textures can be imported without an alpha channel.
                // Their original magenta palette key remains transparent either way.
                clip(abs(texel.r-1)+abs(texel.g)+abs(texel.b-1)-.01);
                fixed4 c=texel*i.color; clip(c.a-.2); return c;
            }
            ENDCG
        }
    }
}
