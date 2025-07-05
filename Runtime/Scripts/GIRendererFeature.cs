using NUnit.Framework.Constraints;
using System;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace RunaeMystica.Rendering
{
	public partial class GIRendererFeature : ScriptableRendererFeature
	{
		[SerializeField]
		private Settings settings = null;

		private EmissionMapRenderPass emissionMapPass;

		private RadianceCascadesRenderPass radianceCascadesPass;

		public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
		{
			renderer.EnqueuePass(emissionMapPass);
			renderer.EnqueuePass(radianceCascadesPass);
		}

		public override void Create()
		{
			emissionMapPass = new EmissionMapRenderPass(settings);
			radianceCascadesPass = new RadianceCascadesRenderPass(settings);

			emissionMapPass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
			radianceCascadesPass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
		}

		[Serializable]
		public class Settings
		{
			public int rayCount = 32;

			public int maxSteps = 64;

			[Range(0.0f, 1.0f)]
			public float intervalSplit = 0.125f;

			public bool bilinearSampling = false;
		}

		public class GIContextData : ContextItem
		{
			public TextureHandle emissionMap;

			public TextureHandle emissionSdf;

			public override void Reset()
			{
				emissionMap = TextureHandle.nullHandle;
				emissionSdf = TextureHandle.nullHandle;
			}
		}
	}
}