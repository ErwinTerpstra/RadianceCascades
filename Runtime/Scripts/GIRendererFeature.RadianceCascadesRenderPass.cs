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

				var rcDesc = new RenderTextureDescriptor(colorDescriptor.width, colorDescriptor.height, RenderTextureFormat.ARGBFloat);
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

				TextureHandle previous = rcBufferA;
				int passCount = 2;
				for (int i = passCount; i >= 1; --i)
				{
					int baseRayCount = settings.rayCount;
					int rayCount = (int) Mathf.Pow(baseRayCount, i);

					MaterialPropertyBlock materialProperties = new MaterialPropertyBlock();
					materialProperties.SetInt("_BaseRayCount", baseRayCount);
					materialProperties.SetInt("_RayCount", rayCount);
					materialProperties.SetInt("_MaxSteps", settings.maxSteps);
					materialProperties.SetFloat("_IntervalSplit", settings.intervalSplit);
					//materialProperties.SetTexture("_EmissionSDF", contextData.emissionSdf);

					TextureHandle target = (passCount - i) % 2 == 0 ? rcBufferB : rcBufferA;

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