package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.EntityTrackingUniforms;
import net.irisshaders.iris.gl.uniform.UniformHolder;
import net.irisshaders.iris.shaderpack.IdMap;
import net.irisshaders.iris.shaderpack.properties.PackDirectives;
import net.irisshaders.iris.uniforms.CommonUniforms;
import net.irisshaders.iris.uniforms.FrameUpdateNotifier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = CommonUniforms.class, remap = false)
public class MixinCommonUniforms {
	@Inject(method = "addNonDynamicUniforms", at = @At("TAIL"))
	private static void lumen$tracking(UniformHolder uniforms, IdMap idMap, PackDirectives directives, FrameUpdateNotifier notifier, CallbackInfo ci) {
		EntityTrackingUniforms.addEntityTrackingUniforms(uniforms);
	}
}
