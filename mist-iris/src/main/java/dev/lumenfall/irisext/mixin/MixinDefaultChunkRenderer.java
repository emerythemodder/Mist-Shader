package dev.lumenfall.irisext.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import com.llamalad7.mixinextras.sugar.Local;
import dev.lumenfall.irisext.LumenPerf;
import net.caffeinemc.mods.sodium.client.render.chunk.DefaultChunkRenderer;
import net.caffeinemc.mods.sodium.client.render.chunk.LocalSectionIndex;
import net.caffeinemc.mods.sodium.client.render.chunk.region.RenderRegion;
import net.caffeinemc.mods.sodium.client.util.iterator.ByteIterator;
import net.irisshaders.iris.shadows.ShadowRenderingState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;

@Mixin(value = DefaultChunkRenderer.class, remap = false)
public class MixinDefaultChunkRenderer {
	@Unique private static int lumen$lastSection;

	@WrapOperation(method = "fillCommandBuffer", at = @At(value = "INVOKE", target = "Lnet/caffeinemc/mods/sodium/client/util/iterator/ByteIterator;nextByteAsInt()I"))
	private static int lumen$trackSection(ByteIterator iterator, Operation<Integer> original) {
		int index = original.call(iterator);
		lumen$lastSection = index;
		return index;
	}

	@WrapOperation(method = "fillCommandBuffer", at = @At(value = "INVOKE", target = "Lnet/caffeinemc/mods/sodium/client/render/chunk/data/SectionRenderDataUnsafe;getSliceMask(J)I"))
	private static int lumen$skipSection(long pointer, Operation<Integer> original, @Local(argsOnly = true) RenderRegion region) {
		int mask = original.call(pointer);
		if (mask != 0 && LumenPerf.active && ShadowRenderingState.areShadowsCurrentlyBeingRendered()) {
			int cx = region.getChunkX() + LocalSectionIndex.unpackX(lumen$lastSection);
			int cz = region.getChunkZ() + LocalSectionIndex.unpackZ(lumen$lastSection);
			if (!LumenPerf.drawSection(cx, cz)) return 0;
		}
		return mask;
	}
}
