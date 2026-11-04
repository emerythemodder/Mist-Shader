package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.VertexNeighbors;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexEncoder;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = ChunkVertexEncoder.Vertex.class, remap = false)
public class MixinSodiumVertex implements VertexNeighbors {
	@Unique private final BlockNeighborData lumen$neighbors = new BlockNeighborData();

	@Override
	public BlockNeighborData lumen$neighbors() {
		return lumen$neighbors;
	}

	@Inject(method = "copyVertexTo", at = @At("HEAD"))
	private static void lumen$copy(ChunkVertexEncoder.Vertex from, ChunkVertexEncoder.Vertex to, CallbackInfo ci) {
		((VertexNeighbors) to).lumen$neighbors().copyFrom(((VertexNeighbors) from).lumen$neighbors());
	}
}
