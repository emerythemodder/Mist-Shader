package dev.lumenfall.irisext.mixin;

import com.llamalad7.mixinextras.sugar.Local;
import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.NeighborHolder;
import dev.lumenfall.irisext.VertexNeighbors;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.BlockRenderer;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.material.Material;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexEncoder;
import net.caffeinemc.mods.sodium.client.render.model.MutableQuadViewImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = BlockRenderer.class, remap = false)
public class MixinBlockRenderer implements NeighborHolder {
	@Unique private final BlockNeighborData lumen$neighbors = new BlockNeighborData();

	@Override
	public BlockNeighborData lumen$neighbors() {
		return lumen$neighbors;
	}

	@Inject(method = "bufferQuad", at = @At(value = "FIELD", target = "Lnet/caffeinemc/mods/sodium/client/render/chunk/vertex/format/ChunkVertexEncoder$Vertex;x:F"))
	private void lumen$vertexNeighbors(MutableQuadViewImpl quad, float[] brightnesses, Material material, CallbackInfo ci, @Local ChunkVertexEncoder.Vertex vertex) {
		if (BlockNeighborData.enabled) ((VertexNeighbors) vertex).lumen$neighbors().copyFrom(lumen$neighbors);
	}
}
