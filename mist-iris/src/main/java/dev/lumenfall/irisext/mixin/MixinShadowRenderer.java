package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.LumenPerf;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.mixin.LevelRendererAccessor;
import net.irisshaders.iris.pipeline.IrisRenderingPipeline;
import net.irisshaders.iris.pipeline.WorldRenderingPipeline;
import net.irisshaders.iris.shadows.ShadowRenderer;
import net.minecraft.client.Camera;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = ShadowRenderer.class, remap = false)
public class MixinShadowRenderer {
	@Inject(method = "renderShadows", at = @At("HEAD"))
	private void lumen$beginShadowPass(LevelRendererAccessor levelRenderer, Camera playerCamera, CameraRenderState renderState, CallbackInfo ci) {
		LumenPerf.active = false;
		if (LumenPerf.rotation == 0) return;
		WorldRenderingPipeline pipeline = Iris.getPipelineManager().getPipelineNullable();
		if (!(pipeline instanceof IrisRenderingPipeline)) return;
		Vec3 cam = playerCamera.position();
		LumenPerf.beginShadowPass(((IrisRenderingPipelineAccessor) pipeline).lumen$customImages(), cam.x, cam.z);
	}

	@Inject(method = "renderShadows", at = @At("RETURN"))
	private void lumen$endShadowPass(LevelRendererAccessor levelRenderer, Camera playerCamera, CameraRenderState renderState, CallbackInfo ci) {
		LumenPerf.active = false;
	}
}
