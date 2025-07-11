using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

namespace RunaeMystica.Rendering
{
	public partial class GIRendererFeature
	{
		private class RadianceCascadesRenderPass : ScriptableRenderPass
		{

			private readonly Settings settings;

			private Material rcMaterial;

			public RadianceCascadesRenderPass(Settings settings)
			{
				this.settings = settings;

				rcMaterial = new Material(Shader.Find("Hidden/RadianceCascades"));
			}

			public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
			{
				UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
				UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
				UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
				UniversalLightData lightData = frameData.Get<UniversalLightData>();

				if (cameraData.cameraType != CameraType.Game)
					return;

				TextureDesc colorDescriptor = resourceData.activeColorTexture.GetDescriptor(renderGraph);

				var rcDesc = new RenderTextureDescriptor(colorDescriptor.width, colorDescriptor.height, RenderTextureFormat.ARGB2101010);
				rcDesc.sRGB = true;

				FilterMode filterMode = settings.bilinearSampling ? FilterMode.Bilinear : FilterMode.Point;
				var rcBufferA = UniversalRenderer.CreateRenderGraphTexture(renderGraph, rcDesc, "EmissionRC_A", true, filterMode: filterMode);
				var rcBufferB = UniversalRenderer.CreateRenderGraphTexture(renderGraph, rcDesc, "EmissionRC_B", true, filterMode: filterMode);

				GIContextData contextData;
				using (var builder = renderGraph.AddRasterRenderPass<PassData>("GenerateEmissionRC/AssignGlobals", out var passData))
				{
					contextData = frameData.Get<GIContextData>();

					builder.AllowGlobalStateModification(true);
					builder.AllowPassCulling(false);
					builder.SetGlobalTextureAfterPass(contextData.emissionMap, Shader.PropertyToID("_EmissionMap"));
					builder.SetGlobalTextureAfterPass(contextData.emissionSdf, Shader.PropertyToID("_EmissionSDF"));
					builder.SetRenderFunc<PassData>((passData, ctx) => { });
				}

				// Determine the diagonal resolution
				int width = colorDescriptor.width;
				int height = colorDescriptor.height;
				float diagonal = Mathf.Sqrt(
					width * width + height * height
				);

				// Our calculation for number of cascades
				int baseRayCount = (int) Mathf.Pow(4, settings.rayCountExponent);
				int cascadeCount = Mathf.CeilToInt(
					Mathf.Log(diagonal) / Mathf.Log(baseRayCount)
				);	

				TextureHandle previous = rcBufferA;
				for (int i = cascadeCount - 1; i >= 0; --i)
				{
					MaterialPropertyBlock materialProperties = new MaterialPropertyBlock();
					materialProperties.SetInt("_BaseRayCount", baseRayCount);
					materialProperties.SetInt("_MaxSteps", settings.maxSteps);

					materialProperties.SetInt("_CascadeIndex", i);
					materialProperties.SetInt("_CascadeCount", cascadeCount);

					TextureHandle target = (cascadeCount - 1 - i) % 2 == 0 ? rcBufferB : rcBufferA;

					renderGraph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters
					(
						previous, target,
						rcMaterial, rcMaterial.FindPass("CalculateCascade"),
						mpb: materialProperties
					), $"GenerateEmissionRC/CascadePass");

					previous = target;
				}

				using (var builder = renderGraph.AddRasterRenderPass("GenerateEmissionRC/SetMaterialProperties", out PassData passData))
				{
					builder.UseAllGlobalTextures(true);
					builder.AllowPassCulling(false);
					builder.AllowGlobalStateModification(true);

					builder.SetRenderFunc((PassData passData, RasterGraphContext ctx) => { });
					builder.SetGlobalTextureAfterPass(previous, Shader.PropertyToID("_EmissionRC"));
				}
			}

			private class PassData
			{

			}

		}
	}
}