package dev.lumenfall.irisext.mixin;

import com.google.common.collect.ImmutableList;
import net.irisshaders.iris.gl.shader.StandardMacros;
import net.irisshaders.iris.helpers.StringPair;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = StandardMacros.class, remap = false)
public class MixinStandardMacros {
	@Inject(method = "createStandardEnvironmentDefines", at = @At("RETURN"), cancellable = true)
	private static void lumen$define(CallbackInfoReturnable<ImmutableList<StringPair>> cir) {
		cir.setReturnValue(ImmutableList.<StringPair>builder().addAll(cir.getReturnValue()).add(new StringPair("LUMENFALL_EXT", "1")).build());
	}
}
