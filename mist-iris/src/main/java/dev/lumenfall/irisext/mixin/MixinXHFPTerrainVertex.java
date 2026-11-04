package dev.lumenfall.irisext.mixin;

import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.VertexNeighbors;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexEncoder;
import net.irisshaders.iris.vertices.sodium.terrain.XHFPTerrainVertex;
import org.lwjgl.system.MemoryUtil;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = XHFPTerrainVertex.class, remap = false)
public class MixinXHFPTerrainVertex {
	@Unique private static final int LUMEN$IRIS_STRIDE = 36;

	@Shadow @Final private int stride;

	@Inject(method = "write", at = @At("HEAD"))
	private void lumen$writeNeighbors(long ptr, int material, ChunkVertexEncoder.Vertex[] vertices, int section, CallbackInfoReturnable<Long> cir) {
		if (!BlockNeighborData.enabled || stride < LUMEN$IRIS_STRIDE + 16) return;

		float ax = vertices[2].x - vertices[0].x, ay = vertices[2].y - vertices[0].y, az = vertices[2].z - vertices[0].z;
		float bx = vertices[3].x - vertices[1].x, by = vertices[3].y - vertices[1].y, bz = vertices[3].z - vertices[1].z;
		int face = BlockNeighborData.faceFromNormal(ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx);
		long off = stride - 16;
		for (int i = 0; i < 4; i++) {
			BlockNeighborData n = ((VertexNeighbors) vertices[i]).lumen$neighbors();
			long p = ptr + (long) i * stride + off;
			MemoryUtil.memPutInt(p, n.sameBlock);
			MemoryUtil.memPutInt(p + 4L, n.nonAir);
			MemoryUtil.memPutInt(p + 8L, n.solid);
			MemoryUtil.memPutInt(p + 12L, n.packIds(face));
		}
	}
}
