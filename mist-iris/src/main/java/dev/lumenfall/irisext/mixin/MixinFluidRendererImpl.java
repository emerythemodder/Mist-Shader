package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.NeighborHolder;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.DefaultFluidRenderer;
import net.caffeinemc.mods.sodium.fabric.render.FluidRendererImpl;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;

@Mixin(value = FluidRendererImpl.class, remap = false)
public class MixinFluidRendererImpl implements NeighborHolder {
	@Shadow @Final private DefaultFluidRenderer defaultRenderer;

	@Override
	public BlockNeighborData lumen$neighbors() {
		return ((NeighborHolder) this.defaultRenderer).lumen$neighbors();
	}
}
