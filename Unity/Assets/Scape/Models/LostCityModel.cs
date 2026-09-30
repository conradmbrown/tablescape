using System;
using System.IO;
using UnityEngine;

namespace Scape.Assets
{
    // Native revision-274 .ob2 decoder. Reads source assets without a game client.
    // Format reference: LostCityRS/Client-Java, branch 274, Model.unpack/Model(int).
    public sealed class LostCityModel
    {
        public Vector3[] vertices;
        public int[] a, b, c, colour, renderType, alpha, vertexLabel, faceLabel, priority;
        public int[] textureP, textureM, textureN;

        sealed class Reader
        {
            readonly byte[] bytes;
            readonly int end;
            int pos;
            public Reader(byte[] bytes, int start, int length)
            {
                if (start < 0 || length < 0 || start > bytes.Length - length) throw new InvalidDataException("Model section bounds");
                this.bytes = bytes; pos = start; end = start + length;
            }
            public int U8() { if (pos >= end) throw new InvalidDataException("Truncated model"); return bytes[pos++]; }
            public int U16() { return (U8() << 8) | U8(); }
            public int Smart()
            {
                if (pos >= end) throw new InvalidDataException("Truncated model delta");
                return bytes[pos] < 128 ? U8() - 64 : U16() - 49152;
            }
        }
        public static LostCityModel Decode(byte[] bytes)
        {
            if (bytes == null || bytes.Length < 18 || bytes.Length > 16000000) throw new InvalidDataException("Invalid model length");
            var footer = new Reader(bytes, bytes.Length - 18, 18);
            int nv = footer.U16(), nf = footer.U16(), nt = footer.U8();
            int types = footer.U8(), pri = footer.U8(), al = footer.U8(), fl = footer.U8(), vl = footer.U8();
            if (types > 1 || al > 1 || fl > 1 || vl > 1) throw new InvalidDataException("Unsupported model flags");
            int nx = footer.U16(), ny = footer.U16(), nz = footer.U16(), ni = footer.U16();
            int cursor = 0;
            Reader Section(int size) { var r = new Reader(bytes, cursor, size); cursor += size; return r; }
            var flags = Section(nv); var orders = Section(nf);
            var priorities = Section(pri == 255 ? nf : 0);
            var faceLabels = Section(fl == 1 ? nf : 0);
            var modes = Section(types == 1 ? nf : 0);
            var vertexLabels = Section(vl == 1 ? nv : 0);
            var alphas = Section(al == 1 ? nf : 0);
            var indices = Section(ni); var colours = Section(nf * 2); var textures = Section(nt * 6);
            var dx = Section(nx); var dy = Section(ny); var dz = Section(nz);
            if (cursor != bytes.Length - 18) throw new InvalidDataException("Model section lengths disagree");
            var m = new LostCityModel {
                vertices = new Vector3[nv], a = new int[nf], b = new int[nf], c = new int[nf],
                colour = new int[nf], renderType = new int[nf], alpha = new int[nf], priority = new int[nf],
                vertexLabel = vl == 1 ? new int[nv] : null, faceLabel = fl == 1 ? new int[nf] : null,
                textureP = new int[nt], textureM = new int[nt], textureN = new int[nt]
            };
            int x = 0, y = 0, z = 0;
            for (int i = 0; i < nv; i++) {
                int flag = flags.U8(); if (flag > 7) throw new InvalidDataException("Vertex flags");
                if ((flag & 1) != 0) x += dx.Smart();
                if ((flag & 2) != 0) y += dy.Smart();
                if ((flag & 4) != 0) z += dz.Smart();
                // Unity is y-up; the original model coordinate system is y-down.
                m.vertices[i] = new Vector3(x, -y, z) / 128f;
                if (vl == 1) m.vertexLabel[i] = vertexLabels.U8();
            }
            for (int i = 0; i < nf; i++) {
                m.colour[i] = colours.U16();
                if (types == 1) m.renderType[i] = modes.U8();
                m.priority[i] = pri == 255 ? priorities.U8() : pri;
                if (al == 1) m.alpha[i] = alphas.U8();
                if (fl == 1) m.faceLabel[i] = faceLabels.U8();
                if ((m.renderType[i] & 2) != 0 && (m.renderType[i] >> 2) >= nt) throw new InvalidDataException("Texture basis index");
            }
            int a = 0, b = 0, c = 0, last = 0;
            for (int i = 0; i < nf; i++) {
                switch (orders.U8()) {
                    case 1: a = indices.Smart() + last; b = indices.Smart() + a; c = indices.Smart() + b; break;
                    case 2: b = c; c = indices.Smart() + last; break;
                    case 3: a = c; c = indices.Smart() + last; break;
                    case 4: int swap = a; a = b; b = swap; c = indices.Smart() + last; break;
                    default: throw new InvalidDataException("Face order");
                }
                if (a < 0 || b < 0 || c < 0 || a >= nv || b >= nv || c >= nv) throw new InvalidDataException("Face vertex index");
                m.a[i] = a; m.b[i] = b; m.c[i] = c; last = c;
            }
            for (int i = 0; i < nt; i++) {
                m.textureP[i] = textures.U16(); m.textureM[i] = textures.U16(); m.textureN[i] = textures.U16();
                if (m.textureP[i] >= nv || m.textureM[i] >= nv || m.textureN[i] >= nv) throw new InvalidDataException("Texture vertex index");
            }
            return m;
        }
        public Vector2 TextureUv(int face, int vertex)
        {
            int basis = renderType[face] >> 2;
            Vector3 p = vertices[textureP[basis]], u = vertices[textureM[basis]] - p, v = vertices[textureN[basis]] - p;
            Vector3 d = vertices[vertex] - p;
            float uu = Vector3.Dot(u,u), vv = Vector3.Dot(v,v), uv = Vector3.Dot(u,v), du = Vector3.Dot(d,u), dv = Vector3.Dot(d,v);
            float det = uu * vv - uv * uv;
            return Mathf.Abs(det) < 1e-10f ? Vector2.zero : new Vector2((du * vv - dv * uv) / det, (dv * uu - du * uv) / det);
        }
        public static Color PaletteColour(int packed)
        {
            // Original 6-bit hue, 3-bit saturation, 7-bit lightness palette.
            float h = (packed >> 10) / 64f + 1f / 128f;
            float s = ((packed >> 7) & 7) / 8f + 1f / 16f;
            float l = (packed & 127) / 128f;
            float q = l < .5f ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
            float Hue(float t) { t = Mathf.Repeat(t,1); return t < 1f/6 ? p + (q-p)*6*t : t < .5f ? q : t < 2f/3 ? p+(q-p)*(2f/3-t)*6 : p; }
            return new Color(Hue(h+1f/3), Hue(h), Hue(h-1f/3), 1);
        }
    }
}
