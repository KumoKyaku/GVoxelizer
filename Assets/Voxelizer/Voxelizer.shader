Shader "Voxelizer Effects"
{
    Properties
    {
        [Header(Base Properties)]
        _Color("Color", Color) = (1, 1, 1, 1)
        _MainTex("Albedo", 2D) = "white" {}
        //_Glossiness("Smoothness", Range(0, 1)) = 0.5
        //[Gamma] _Metallic("Metallic", Range(0, 1)) = 0
		[Header(Gloss SpecColor)]
		[MaterialToggle] _useSpec ("useSpec", Float ) = 0
		_Gloss ("Gloss", Range(0, 1)) = 0.5
		_SpecColor ("Spec Color", Color) = (1,1,1,1)

		[Header(BlendMode)]
		[Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend Mode", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend Mode", Float) = 10

		[Header(Effect Properteis)]
        [HDR] _EdgeColor("Edge Color", Color) = (0, 1, 1, 1)
		[HDR] _FaceColor("Face Color", Color) = (0, 0.5, 1, 1)

		[Header(Cube fx)]
		_CubeRatio ("_CubeRatio", Range(0, 1)) = 0.15

		[Space]
		_TriangleScale ("TriangleScale", Range(0, 10)) = 6
		_StartTrans ("StartTrans", Range(0, 1)) = 0.25
		_EndTrans ("EndTrans(Must be larger than StartTrans)", Range(0, 1)) = 0.5
		_CubeScale ("CubeSizeScale", Range(0, 1)) = 0.25

		[Space]
		[KeywordEnum(Y, YN, Z, ZN, X, XN)] _FadeOut ("FadeOut", Float) = 0

		[Header(Dust)]
		_DustMoveScale ("DustMoveScale", Range(0, 10)) = 1.0
        
    }
    SubShader
    {
        Tags{ "RenderType" = "Opeque" "Queue"="Geometry"}

        Pass
        {
			Name "Deferred"
            Tags { "LightMode"="Deferred" }

            CGPROGRAM
            #pragma target 4.0
			#define UNITY_PASS_DEFERRED
            #pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag
            #pragma multi_compile_prepassfinal noshadowmask nodynlightmap nodirlightmap nolightmap
			#pragma multi_compile _FADEOUT_Y _FADEOUT_YN _FADEOUT_Z _FADEOUT_ZN _FADEOUT_X _FADEOUT_XN
            #include "Voxelizer.cginc"
            ENDCG
        }

        pass
		{
			Name "FOWARD"

			Tags
			{
				"LightMode" = "ForwardBase"	
			}

			Blend [_SrcBlend] [_DstBlend]

			CGPROGRAM

			#pragma target 4.0
			#define UNITY_PASS_FORWARDBASE
			#pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag

			//#pragma multi_compile_prepassfinal noshadowmask nodynlightmap nodirlightmap nolightmap
            //#pragma multi_compile_fwdadd_fullshadows
            //#pragma multi_compile_fog
			#pragma multi_compile _FADEOUT_Y _FADEOUT_YN _FADEOUT_Z _FADEOUT_ZN _FADEOUT_X _FADEOUT_XN
			#include "Voxelizer.cginc"

			ENDCG
		}

		pass
		{
			Name "FORWARD_DELTA"

			Tags
			{
				"LightMode" = "ForwardAdd"	
			}

			CGPROGRAM

			#pragma target 4.0
			#define UNITY_PASS_FORWARDADD
			#pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag

			//#pragma multi_compile_prepassfinal noshadowmask nodynlightmap nodirlightmap nolightmap
            //#pragma multi_compile_fwdadd_fullshadows
            //#pragma multi_compile_fog
			#pragma multi_compile _FADEOUT_Y _FADEOUT_YN _FADEOUT_Z _FADEOUT_ZN _FADEOUT_X _FADEOUT_XN
			#include "Voxelizer.cginc"

			ENDCG
		}

		pass
		{
			Name "FOWARDSHADOW"

			Tags
			{
				"LightMode" = "ShadowCaster"	
			}

			CGPROGRAM

			#pragma target 4.0
			#define UNITY_PASS_SHADOWCASTER
			#pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag

			//#pragma multi_compile_prepassfinal noshadowmask nodynlightmap nodirlightmap nolightmap
            //#pragma multi_compile_fwdadd_fullshadows
            //#pragma multi_compile_fog
			#pragma multi_compile _FADEOUT_Y _FADEOUT_YN _FADEOUT_Z _FADEOUT_ZN _FADEOUT_X _FADEOUT_XN
			#include "Voxelizer.cginc"

			ENDCG
		}
    }
}
