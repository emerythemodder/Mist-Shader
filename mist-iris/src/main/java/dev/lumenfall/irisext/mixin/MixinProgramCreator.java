package dev.lumenfall.irisext.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import net.irisshaders.iris.gl.shader.ProgramCreator;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;

@Mixin(value = ProgramCreator.class, remap = false)
public class MixinProgramCreator {
	@WrapOperation(method = "create", at = @At(value = "INVOKE", target = "Lcom/mojang/renderpearl/backend/opengl/GlStateManager;_glBindAttribLocation(IILjava/lang/CharSequence;)V"))
	private static void lumen$bindNeighbors(int program, int index, CharSequence name, Operation<Void> original) {
		original.call(program, index, name);
		if (index == 14 && "at_midBlock".contentEquals(name)) original.call(program, 15, "at_neighbors");
	}
}
