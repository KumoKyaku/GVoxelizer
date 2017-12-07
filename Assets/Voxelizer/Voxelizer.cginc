///Coder:Kumo Kyaku   https://github.com/KumoKyaku/GVoxelizer
///Refrences : https://github.com/keijiro/GVoxelizer

#include "Common.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardUtils.cginc"
#include "AutoLight.cginc"
#include "Lighting.cginc"
#include "SimplexNoise3D.hlsl"

// Cube map shadow caster; Used to render point light shadows on platforms
// that lacks depth cube map support.
#if defined(SHADOWS_CUBE) && !defined(SHADOWS_CUBE_IN_DEPTH_TEX)
#define PASS_CUBE_SHADOWCASTER
#endif

///基础属性
float4 _Color;
sampler2D _MainTex;
float4 _MainTex_ST;

///光泽 和 高光
float _useSpec;
float _Gloss;
//float4 _SpecColor;

///边缘
float4 _EdgeColor;
float4 _FaceColor;
///变形系数

float _CubeRatio;
float _TriangleScale;
float _StartTrans;
float _EndTrans;
float _CubeScale;

///星屑移动缩放
float _DustMoveScale;

///变形参数
// Dynamic properties
float4 _EffectVector;


struct Varyings
{
    float4 position : SV_POSITION;

#if defined(PASS_CUBE_SHADOWCASTER)
    // Cube map shadow caster pass
    float3 shadow : TEXCOORD0;

#elif defined(UNITY_PASS_SHADOWCASTER)
    // Default shadow caster pass

#else
    // GBuffer construction pass
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
    half3 ambient : TEXCOORD1;
    float4 edge : TEXCOORD2; // barycentric coord (xyz), emission (w)
    float4 wpos_ch : TEXCOORD3; // world position (xyz), channel select (w)

#endif
};

//
// Vertex stage
//

struct v2g
{
    float4 pos : SV_POSITION;
	float3 normal : NORMAL;
	float2 uv0 : TEXCOORD0;
	float4 posWorld : TEXCOORD1;
	// LIGHTING_COORDS(3,4)
    // UNITY_FOG_COORDS(5)
};

v2g vert(appdata_base v)
{
	v2g o = (v2g)0;

	o.pos = UnityObjectToClipPos( v.vertex );
    o.normal = UnityObjectToWorldNormal(v.normal);
	o.uv0 = v.texcoord;	
	o.posWorld = mul(unity_ObjectToWorld, v.vertex);
	o.posWorld = float4(o.posWorld.xyz,0);
	// UNITY_TRANSFER_FOG(o,o.pos);
    // TRANSFER_VERTEX_TO_FRAGMENT(o)
	return o;
}

struct g2f
{
	float4 pos : SV_POSITION;

#if defined(PASS_CUBE_SHADOWCASTER)
    // Cube map shadow caster pass
    float3 shadow : TEXCOORD0;

#elif defined(UNITY_PASS_SHADOWCASTER)

#else
	float3 normal : NORMAL;
	float2 uv0 : TEXCOORD0;
	float4 posWorld : TEXCOORD1;
	float4 edge : TEXCOORD2;
	//LIGHTING_COORDS(3,4)
    // UNITY_FOG_COORDS(5)
#endif

};

//
// Geometry stage
//

Varyings VertexOutput(float3 wpos, half3 wnrm, float2 uv,
                      float4 edge = 0.5, float channel = 0)
{
    Varyings o;

#if defined(PASS_CUBE_SHADOWCASTER)
    // Cube map shadow caster pass: Transfer the shadow vector.
    o.position = UnityWorldToClipPos(float4(wpos, 1));
    o.shadow = wpos - _LightPositionRange.xyz;

#elif defined(UNITY_PASS_SHADOWCASTER)
    // Default shadow caster pass: Apply the shadow bias.
    float scos = dot(wnrm, normalize(UnityWorldSpaceLightDir(wpos)));
    wpos -= wnrm * unity_LightShadowBias.z * sqrt(1 - scos * scos);
    o.position = UnityApplyLinearShadowBias(UnityWorldToClipPos(float4(wpos, 1)));

#else
    // GBuffer construction pass
    o.position = UnityWorldToClipPos(float4(wpos, 1));
    o.normal = wnrm;
    o.texcoord = uv;
    o.ambient = ShadeSHPerVertex(wnrm, 0);
    o.edge = edge;
    o.wpos_ch = float4(wpos, channel);

#endif
    return o;
}

g2f VertexOutput(float4 pos, float3 normal, float2 uv,float4 posWorld,
float4 edge = 0.5)
{
	g2f o;

#if defined(PASS_CUBE_SHADOWCASTER)
    // Cube map shadow caster pass: Transfer the shadow vector.
    o.pos = UnityWorldToClipPos(float4(posWorld.xyz, 1));
    o.shadow = posWorld.xyz - _LightPositionRange.xyz;

#elif defined(UNITY_PASS_SHADOWCASTER)
    // Default shadow caster pass: Apply the shadow bias.
    float scos = dot(normal, normalize(UnityWorldSpaceLightDir(posWorld)));
    float3 posWorld2 = posWorld.xyz - normal * unity_LightShadowBias.z * sqrt(1 - scos * scos);
	o.pos = UnityApplyLinearShadowBias(UnityWorldToClipPos(float4(posWorld2, 1)));

#else
    
	o.pos = pos;
	o.normal = normal;
	o.uv0 = uv;
	o.posWorld = posWorld;
	o.edge = edge;

#endif
	return o;
}

g2f VertexOutput(v2g v)
{
	return VertexOutput(v.pos, v.normal, v.uv0, v.posWorld);
}

g2f CubeVertex(
    float4 wpos, half3 wnrm_tri, half3 wnrm_cube, float2 uv,
    float3 bary_tri, float2 bary_cube, float morph, float emission
)
{
	float4 posWorld = wpos;
    float3 wnrm = normalize(lerp(wnrm_tri, wnrm_cube, morph));
    float3 bary = lerp(bary_tri, float3(bary_cube, 0.5), morph);
    return VertexOutput(UnityWorldToClipPos(posWorld), wnrm, uv,posWorld, float4(bary, emission));
}

g2f TriangleVertex(float4 posWorld, float3 normal, float2 uv,
 float3 bary, float emission)
{
    return VertexOutput(UnityWorldToClipPos(posWorld),normal,uv,posWorld,float4(bary, emission));
}

[maxvertexcount(24)]
void geom (triangle v2g input[3],
uint pid : SV_PRIMITIVEID,
inout TriangleStream<g2f> outStream)
{
	v2g v0 = input[0];
	v2g v1 = input[1];
	v2g v2 = input[2];

	float3 p0 = v0.posWorld.xyz;
	float3 p1 = v1.posWorld.xyz;
	float3 p2 = v2.posWorld.xyz;

	float3 n0 = v0.normal;
	float3 n1 = v1.normal;
	float3 n2 = v2.normal;

	float2 uv0 = v0.uv0;
    float2 uv1 = v1.uv0;
    float2 uv2 = v2.uv0;

	float3 center = (p0 + p1 + p2) / 3;

	///相对触发边界位置
	float relativeLocation = 1 - dot(_EffectVector.xyz, center) + _EffectVector.w;

	if(relativeLocation < 0)
	{
#if defined(IsVisibleBeforeEnter)
		///没有进入变形边界
		outStream.Append(VertexOutput(v0));
		outStream.Append(VertexOutput(v1));
		outStream.Append(VertexOutput(v2));
		outStream.RestartStrip();
#endif
		return;
	}

	if(relativeLocation > 1) 
	{
		///超出变形边界 消失
		return;
	}

	// Choose cube/triangle randomly. 877源代码就是这样不知道原因
    uint seed = pid * 877;
	if(Random(seed) < _CubeRatio)
	{
		///变形部分

		///第一步放大三角面
		float t_anim = 1 + relativeLocation * 10 * _TriangleScale;
        float3 t_p0 = lerp(center, p0, t_anim);
        float3 t_p1 = lerp(center, p1, t_anim);
        float3 t_p2 = lerp(center, p2, t_anim);

		// Cube animation
        float rnd = Random(seed + 1); // random number, gradient noise
        float4 snoise = snoise_grad(float3(rnd * 2378.34, relativeLocation * 0.8, 0));

        float move = saturate(relativeLocation * 4 - 3); // stretch/move param
        move = move * move;

        float3 pos = center + snoise.xyz * 0.02; // cube position

		float3 scale = 1;

#if _FADEOUT_Y

        pos.y += move * rnd;
        scale = float2(1 - move, 1 + move * 5).xyx; // cube scale anim

#elif _FADEOUT_YN

		pos.y -= move * rnd;
        scale = float2(1 - move, 1 + move * 5).xyx; // cube scale anim

#elif _FADEOUT_Z

 		pos.z += move * rnd;
        scale = float2(1 - move, 1 + move * 5).xxy; // cube scale anim

#elif _FADEOUT_ZN

 		pos.z -= move * rnd;
        scale = float2(1 - move, 1 + move * 5).xxy; // cube scale anim

#elif _FADEOUT_X

 		pos.x += move * rnd;
        scale = float2(1 - move, 1 + move * 5).yxx; // cube scale anim

#elif _FADEOUT_XN

 		pos.x -= move * rnd;
        scale = float2(1 - move, 1 + move * 5).yxx; // cube scale anim

#endif

        scale *= _CubeScale * 0.2 * saturate(1 + snoise.w * 2);

        float edge = saturate(relativeLocation * 5); // Edge color (emission power)

		///_TestP0开始向正方形变形的起始点，_TestP完全变形成正方形的点
        float morph = smoothstep(_StartTrans, _EndTrans, relativeLocation);

        float4 c_p0 = float4(lerp(t_p2, pos + float3(-1, -1, -1) * scale, morph) , morph);
        float4 c_p1 = float4(lerp(t_p2, pos + float3(+1, -1, -1) * scale, morph) , morph);
        float4 c_p2 = float4(lerp(t_p0, pos + float3(-1, +1, -1) * scale, morph) , morph);
        float4 c_p3 = float4(lerp(t_p1, pos + float3(+1, +1, -1) * scale, morph) , morph);
        float4 c_p4 = float4(lerp(t_p2, pos + float3(-1, -1, +1) * scale, morph) , morph);
        float4 c_p5 = float4(lerp(t_p2, pos + float3(+1, -1, +1) * scale, morph) , morph);
        float4 c_p6 = float4(lerp(t_p0, pos + float3(-1, +1, +1) * scale, morph) , morph);
        float4 c_p7 = float4(lerp(t_p1, pos + float3(+1, +1, +1) * scale, morph) , morph);

		// Vertex outputs

        float3 c_n = float3(-1, 0, 0);
        outStream.Append(CubeVertex(c_p2, n0, c_n, uv0, float3(0, 0, 1), float2(0, 0), morph, edge));
        outStream.Append(CubeVertex(c_p0, n2, c_n, uv2, float3(1, 0, 0), float2(1, 0), morph, edge));
        outStream.Append(CubeVertex(c_p6, n0, c_n, uv0, float3(0, 0, 1), float2(0, 1), morph, edge));
        outStream.Append(CubeVertex(c_p4, n2, c_n, uv2, float3(1, 0, 0), float2(1, 1), morph, edge));
        outStream.RestartStrip();

        c_n = float3(1, 0, 0);
        outStream.Append(CubeVertex(c_p1, n2, c_n, uv2, float3(0, 0, 1), float2(0, 0), morph, edge));
        outStream.Append(CubeVertex(c_p3, n1, c_n, uv1, float3(1, 0, 0), float2(1, 0), morph, edge));
        outStream.Append(CubeVertex(c_p5, n2, c_n, uv2, float3(0, 0, 1), float2(0, 1), morph, edge));
        outStream.Append(CubeVertex(c_p7, n1, c_n, uv1, float3(1, 0, 0), float2(1, 1), morph, edge));
        outStream.RestartStrip();

        c_n = float3(0, -1, 0);
        outStream.Append(CubeVertex(c_p0, n2, c_n, uv2, float3(1, 0, 0), float2(0, 0), morph, edge));
        outStream.Append(CubeVertex(c_p1, n2, c_n, uv2, float3(1, 0, 0), float2(1, 0), morph, edge));
        outStream.Append(CubeVertex(c_p4, n2, c_n, uv2, float3(1, 0, 0), float2(0, 1), morph, edge));
        outStream.Append(CubeVertex(c_p5, n2, c_n, uv2, float3(1, 0, 0), float2(1, 1), morph, edge));
        outStream.RestartStrip();

        c_n = float3(0, 1, 0);
        outStream.Append(CubeVertex(c_p3, n1, c_n, uv1, float3(0, 0, 1), float2(0, 0), morph, edge));
        outStream.Append(CubeVertex(c_p2, n0, c_n, uv0, float3(1, 0, 0), float2(1, 0), morph, edge));
        outStream.Append(CubeVertex(c_p7, n1, c_n, uv1, float3(0, 0, 1), float2(0, 1), morph, edge));
        outStream.Append(CubeVertex(c_p6, n0, c_n, uv0, float3(1, 0, 0), float2(1, 1), morph, edge));
        outStream.RestartStrip();

        c_n = float3(0, 0, -1);
        outStream.Append(CubeVertex(c_p1, n2, c_n, uv2, float3(0, 0, 1), float2(0, 0), morph, edge));
        outStream.Append(CubeVertex(c_p0, n2, c_n, uv2, float3(0, 0, 1), float2(1, 0), morph, edge));
        outStream.Append(CubeVertex(c_p3, n1, c_n, uv1, float3(0, 1, 0), float2(0, 1), morph, edge));
        outStream.Append(CubeVertex(c_p2, n0, c_n, uv0, float3(1, 0, 0), float2(1, 1), morph, edge));
        outStream.RestartStrip();

        c_n = float3(0, 0, 1);
        outStream.Append(CubeVertex(c_p4, -n2, c_n, uv2, float3(0, 0, 1), float2(0, 0), morph, edge));
        outStream.Append(CubeVertex(c_p5, -n2, c_n, uv2, float3(0, 0, 1), float2(1, 0), morph, edge));
        outStream.Append(CubeVertex(c_p6, -n0, c_n, uv0, float3(0, 1, 0), float2(0, 1), morph, edge));
        outStream.Append(CubeVertex(c_p7, -n1, c_n, uv1, float3(1, 0, 0), float2(1, 1), morph, edge));
        outStream.RestartStrip();
	}
	else
	{
		///碎片部分

		// -- Triangle fx --
        // Simple scattering animation

        // We use smoothstep to make naturally damped linear motion.
        // Q. Why don't you use 1-pow(1-param,2)?
        // A. Smoothstep is cooler than it. Forget Newtonian physics.
        float ss_param = smoothstep(0, 1, relativeLocation);

        // Random motion
        float3 move = RandomVector(seed + 1) * ss_param * 0.5 * _DustMoveScale;

        // Random rotation
        float3 rot_angles = (RandomVector01(seed + 1) - 0.5) * 100;
        float3x3 rot_m = Euler3x3(rot_angles * ss_param);

        // Simple shrink
        float scale = 1 - ss_param;

        // Apply the animation.
        float3 t_p0 = mul(rot_m, p0 - center) * scale + center + move;
        float3 t_p1 = mul(rot_m, p1 - center) * scale + center + move;
        float3 t_p2 = mul(rot_m, p2 - center) * scale + center + move;
        float3 normal = normalize(cross(t_p1 - t_p0, t_p2 - t_p0));

        // Edge color (emission power) animation
        float edge = smoothstep(0, 0.1, relativeLocation); // ease-in
        edge *= 1 + 20 * smoothstep(0, 0.1, 0.1 - relativeLocation); // peak -> release

        // Vertex outputs (front face)
        outStream.Append(TriangleVertex(float4(t_p0,0), normal, uv0, float3(1, 0, 0), edge));
        outStream.Append(TriangleVertex(float4(t_p1,0), normal, uv1, float3(0, 1, 0), edge));
        outStream.Append(TriangleVertex(float4(t_p2,0), normal, uv2, float3(0, 0, 1), edge));
        outStream.RestartStrip();

        // Vertex outputs (back face)
        outStream.Append(TriangleVertex(float4(t_p0,0), -normal, uv0, float3(1, 0, 0), edge));
		outStream.Append(TriangleVertex(float4(t_p1,0), -normal, uv1, float3(0, 1, 0), edge));
        outStream.Append(TriangleVertex(float4(t_p2,0), -normal, uv2, float3(0, 0, 1), edge));

        outStream.RestartStrip();
	}
}

//
// Fragment phase
//

#if defined(PASS_CUBE_SHADOWCASTER)

// Cube map shadow caster pass
half4 frag(v2g input) : SV_Target
{
    float depth = length(input.shadow) + unity_LightShadowBias.x;
    return UnityEncodeCubeShadowDepth(depth * _LightPositionRange.w);
}

#elif defined(UNITY_PASS_SHADOWCASTER)

// Default shadow caster pass
half4 frag() : SV_Target { return 0; }

#elif defined(UNITY_PASS_DEFERRED)

// GBuffer construction pass
void frag(
    g2f input,
    out half4 outGBuffer0 : SV_Target0,
    out half4 outGBuffer1 : SV_Target1,
    out half4 outGBuffer2 : SV_Target2,
    out half4 outEmission : SV_Target3
)
{
    half3 albedo = tex2D(_MainTex, input.uv0).rgb * _Color.rgb;

    // PBS workflow conversion (metallic -> specular)
    half3 c1_diff, c1_spec, c2_diff, c2_spec;
    half not_in_use;

    c1_diff = DiffuseAndSpecularFromMetallic(
        albedo, _Gloss,       // input
        c1_spec, not_in_use      // output
    );

    c2_diff = DiffuseAndSpecularFromMetallic(
        _FaceColor.rgb, _Gloss, // input
        c2_spec, not_in_use      // output
    );

    // Detect fixed-width edges with using screen space derivatives of
    // barycentric coordinates.
    float3 bcc = input.edge.xyz;
    float3 fw = fwidth(bcc);
    float3 edge3 = min(smoothstep(fw / 2, fw,     bcc),
                       smoothstep(fw / 2, fw, 1 - bcc));
    float edge = 1 - min(min(edge3.x, edge3.y), edge3.z);

	float3 emissive = _EdgeColor.rgb * _EdgeColor.a * edge * input.edge.w;

    // Update the GBuffer.
    UnityStandardData data;
    float ch = input.posWorld.w;
    data.diffuseColor = lerp(c1_diff, c2_diff, ch);
    data.occlusion = 1;
    data.specularColor = lerp(c1_spec, c2_spec, ch);
    data.smoothness = _Gloss;
    data.normalWorld = input.normal;
    UnityStandardDataToGbuffer(data, outGBuffer0, outGBuffer1, outGBuffer2);

    // Output ambient light and edge emission to the emission buffer.
    half3 sh = ShadeSHPerPixel(data.normalWorld, ShadeSHPerVertex(input.normal, 0), input.posWorld.xyz);
    outEmission = half4(sh * data.diffuseColor + emissive, 1);
}

#else

float4 frag(g2f i):SV_Target
{

	float3 normalDirection = normalize(i.normal);
	float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

#if defined(UNITY_PASS_FORWARDBASE)
	float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);
#elif defined(UNITY_PASS_FORWARDADD)
	float3 lightDirection = normalize(lerp(_WorldSpaceLightPos0.xyz, _WorldSpaceLightPos0.xyz - i.posWorld.xyz,_WorldSpaceLightPos0.w));
#endif

	//float3 lightColor = _LightColor0.rgb;
	float3 halfDirection = normalize(viewDirection+lightDirection);

	/// Lighting:
	float attenuation = LIGHT_ATTENUATION(i);

	///漫反射
	float4 _Diffuse_var = tex2D(_MainTex,TRANSFORM_TEX(i.uv0, _MainTex));

	float3 diffuse = (_Diffuse_var.rgb*_Color.rgb); // Diffuse Color

	diffuse = lerp(diffuse,_FaceColor.rgb,i.posWorld.w);

	float finalAlpha = lerp(_Color.a * _Diffuse_var.a,_FaceColor.a,i.posWorld.w);

#if defined(UNITY_PASS_FORWARDBASE)
	/// Emissive:自发光
	float3 emissive = (diffuse*UNITY_LIGHTMODEL_AMBIENT.rgb);

	///SpecCube0 反射探针
	float3 reflection = DecodeHDR(UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, halfDirection), unity_SpecCube0_HDR);
	emissive += reflection*0.01;
	///边缘发光
	// Detect fixed-width edges with using screen space derivatives of
    // barycentric coordinates.
    float3 bcc = i.edge.xyz;
    float3 fw = fwidth(bcc);
    float3 edge3 = min(smoothstep(fw / 2, fw,     bcc),
                       smoothstep(fw / 2, fw, 1 - bcc));
    float edge = 1 - min(min(edge3.x, edge3.y), edge3.z);

	emissive += _EdgeColor.rgb * _EdgeColor.a * edge * i.edge.w;

#endif
	///兰伯特光照强度
	float lambert = max(0,dot(lightDirection,normalDirection)); // Lambert

	///计算高光
	float blinn_phong = max(0,dot(normalDirection,halfDirection));
	float blinn_phong_power = pow(blinn_phong,exp2(lerp(1,11,_Gloss)));
	float3 specularColor = lambert*blinn_phong_power*_SpecColor.rgb;
	///是否开启高光
	specularColor = lerp(float3(0,0,0),specularColor,_useSpec);

#if defined(UNITY_PASS_FORWARDBASE)	
	///最终颜色 = 自发光 + （漫反射 + 高光）*灯光*衰减
	float3 finalColor = emissive + (((diffuse*lambert)+specularColor)*_LightColor0.rgb*attenuation);
#elif defined(UNITY_PASS_FORWARDADD)
	float3 finalColor = ((diffuse*lambert)+specularColor)*_LightColor0.rgb*attenuation;
#endif

	fixed4 finalRGBA = fixed4(finalColor,finalAlpha);
	//UNITY_APPLY_FOG(i.fogCoord, finalRGBA);
	return finalRGBA;
}

#endif
