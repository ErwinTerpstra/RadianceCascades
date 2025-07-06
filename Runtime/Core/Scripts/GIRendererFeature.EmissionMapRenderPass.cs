using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

namespace RunaeMystica.Rendering
{
	public partial class GIRendererFeature
	{
		public class EmissionMapRenderPass : ScriptableRenderPass
		{
			private readonly Settings settings;

			private Material jumpFloodMaterial;

			public EmissionMapRenderPass(Settings settings)
			{
				this.settings = settings;

				jumpFloodMaterial = new Material(Shader.Find("Hidden/JumpFlood"));
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

				// Emission map buffer
				var emissionMapDesc = new RenderTextureDescriptor(colorDescriptor.width, colorDescriptor.height, RenderTextureFormat.ARGB2101010);
				var emissionMap = UniversalRenderer.CreateRenderGraphTexture(renderGraph, emissionMapDesc, "EmissionMap", false);

				// Nearest-UV buffers for jump flood
				var sdfBufferDesc = new RenderTextureDescriptor(colorDescriptor.width, colorDescriptor.height, RenderTextureFormat.ARGB2101010);
				var sdfBufferA = UniversalRenderer.CreateRenderGraphTexture(renderGraph, sdfBufferDesc, "EmissionSDF_A", false);
				var sdfBufferB = UniversalRenderer.CreateRenderGraphTexture(renderGraph, sdfBufferDesc, "EmissionSDF_B", false);

				// True single-channel SDF
				// TODO: this could be single-channel, but I'm getting artifacts when taking R16/RFloat and R8 is too low precision.
				// Investigate!
				var sdfDesc = new RenderTextureDescriptor(colorDescriptor.width, colorDescriptor.height, RenderTextureFormat.ARGB2101010);
				var emissionSdf = UniversalRenderer.CreateRenderGraphTexture(renderGraph, sdfDesc, "EmissionSDF", false);

				var rendererListDesc = new RendererListDesc(new ShaderTagId("EmissionMap"), renderingData.cullResults, cameraData.camera);
				rendererListDesc.renderQueueRange = RenderQueueRange.all;
				rendererListDesc.sortingCriteria = SortingCriteria.SortingLayer;

				var rendererList = renderGraph.CreateRendererList(rendererListDesc);

				using (var builder = renderGraph.AddRasterRenderPass("RenderEmissionMap", out PassData passData))
				{
					// Store renderer list in pass data to make it available in renderer function
					passData.rendererList = rendererList;
					passData.settings = settings;

					builder.SetRenderAttachment(emissionMap, 0);
					//builder.SetRenderAttachmentDepth(emissionMap);

					builder.UseAllGlobalTextures(true);
					builder.AllowPassCulling(false);
					builder.UseRendererList(rendererList);
					builder.AllowGlobalStateModification(true);

					builder.SetRenderFunc((PassData passData, RasterGraphContext ctx) =>
					{
						ctx.cmd.ClearRenderTarget(true, true, Color.clear);
						ctx.cmd.DrawRendererList(passData.rendererList);
					});
				}

				// Jump flood requires log2 passes per pixel in a dimension
				int jumpFloodPasses = Mathf.CeilToInt(Mathf.Log(Mathf.Max(emissionMapDesc.width, emissionMapDesc.height), 2));

				// Seed our first buffer with the object positions
				renderGraph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters
				(
					emissionMap, sdfBufferA,
					jumpFloodMaterial, jumpFloodMaterial.FindPass("Seed")
				), "GenerateEmissionSDF/Seed");

				// Ping-pong between buffers to fill the entire buffer
				var sdfSource = sdfBufferA;
				var sdfDestination = sdfBufferB;
				for (int i = 0; i < jumpFloodPasses; ++i)
				{
					MaterialPropertyBlock materialProperties = new MaterialPropertyBlock();
					materialProperties.SetFloat("_Offset", Mathf.Pow(2, jumpFloodPasses - i - 1));

					renderGraph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters
					(
						sdfSource, sdfDestination,
						jumpFloodMaterial, jumpFloodMaterial.FindPass("Filter"),
						mpb: materialProperties
					), $"GenerateEmissionSDF/Filter");

					(sdfSource, sdfDestination) = (sdfDestination, sdfSource);
				}

				// Convert the UV map to a SDF
				renderGraph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters
				(
					sdfSource, emissionSdf,
					jumpFloodMaterial, jumpFloodMaterial.FindPass("ConvertToSDF")
				), "GenerateEmissionSDF/Convert");

				// Store texture references for next passes
				using (var builder = renderGraph.AddRasterRenderPass("CreateFrameData", out PassData passData))
				{
					builder.AllowPassCulling(false);
					builder.SetRenderFunc<PassData>((passData, ctx) => { });

					var contextData = frameData.Create<GIContextData>();
					contextData.emissionMap = emissionMap;
					contextData.emissionSdf = emissionSdf;
				}
			}

			private class PassData
			{
				public RendererListHandle rendererList;

				public Settings settings;
			}

			private class FilterPassData
			{
				public TextureHandle emissionMap;

				public TextureHandle jumpFloodTexture0, jumpFloodTexture1;
			}
		}
	}
}