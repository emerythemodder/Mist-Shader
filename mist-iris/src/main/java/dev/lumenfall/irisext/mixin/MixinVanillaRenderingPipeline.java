package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.LumenPerf;
import net.irisshaders.iris.pipeline.VanillaRenderingPipeline;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = VanillaRenderingPipeline.class, remap = false)
public class MixinVanillaRenderingPipeline {
	@Inject(method = "<init>", at = @At("TAIL"))
	private void lumen$off(CallbackInfo ci) {
		BlockNeighborData.enabled = false;
		LumenPerf.configure(java.util.Map.of());
	}
}
