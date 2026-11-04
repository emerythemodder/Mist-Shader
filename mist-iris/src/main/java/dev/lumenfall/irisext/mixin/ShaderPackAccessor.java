package dev.lumenfall.irisext.mixin;

import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.properties.ShaderProperties;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(value = ShaderPack.class, remap = false)
public interface ShaderPackAccessor {
	@Accessor("shaderProperties")
	ShaderProperties lumen$properties();
}
