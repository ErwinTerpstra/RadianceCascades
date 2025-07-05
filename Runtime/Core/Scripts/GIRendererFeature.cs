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
			[Range(1, 4)]
			public int rayCountExponent = 2;

			public int maxSteps = 32;

			public bool bilinearSampling = true;
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