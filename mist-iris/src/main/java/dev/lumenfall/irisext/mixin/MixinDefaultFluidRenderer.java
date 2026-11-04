package dev.lumenfall.irisext.mixin;

import com.llamalad7.mixinextras.sugar.Local;
import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.NeighborHolder;
import dev.lumenfall.irisext.VertexNeighbors;
import net.caffeinemc.mods.sodium.client.model.quad.ModelQuadView;
import net.caffeinemc.mods.sodium.client.model.quad.properties.ModelQuadFacing;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.buffers.ChunkModelBuilder;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.DefaultFluidRenderer;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.material.Material;
import net.caffeinemc.mods.sodium.client.render.chunk.translucent_sorting.TranslucentGeometryCollector;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexEncoder;
import net.minecraft.core.BlockPos;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = DefaultFluidRenderer.class, remap = false)
public class MixinDefaultFluidRenderer implements NeighborHolder {
	@Unique private final BlockNeighborData lumen$neighbors = new BlockNeighborData();

	@Override
	public BlockNeighborData lumen$neighbors() {
		return lumen$neighbors;
	}

	@Inject(method = "writeQuad", at = @At(value = "FIELD", target = "Lnet/caffeinemc/mods/sodium/client/render/chunk/vertex/format/ChunkVertexEncoder$Vertex;x:F"))
	private void lumen$vertexNeighbors(ChunkModelBuilder builder, TranslucentGeometryCollector collector, Material material, BlockPos offset, ModelQuadView quad, ModelQuadFacing facing, boolean flip, CallbackInfo ci, @Local ChunkVertexEncoder.Vertex vertex) {
		if (BlockNeighborData.enabled) ((VertexNeighbors) vertex).lumen$neighbors().copyFrom(lumen$neighbors);
	}
}
