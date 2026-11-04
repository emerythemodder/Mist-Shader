package dev.lumenfall.irisext.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.vertex.VertexFormat;
import dev.lumenfall.irisext.BlockNeighborData;
import it.unimi.dsi.fastutil.bytes.Byte2ObjectMap;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexType;
import net.irisshaders.iris.vertices.sodium.terrain.FormatAnalyzer;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = FormatAnalyzer.class, remap = false)
public class MixinFormatAnalyzer {
	@Shadow @Final private static Byte2ObjectMap<ChunkVertexType> classMap;
	@Unique private static int lumen$builtWith = -1;

	@Inject(method = "createFormat", at = @At("HEAD"))
	private static void lumen$resetCache(boolean blockId, boolean normal, boolean midUV, boolean midBlock, CallbackInfoReturnable<ChunkVertexType> cir) {
		int now = BlockNeighborData.enabled ? 1 : 0;
		if (now != lumen$builtWith) {
			classMap.clear();
			lumen$builtWith = now;
		}
	}

	@WrapOperation(method = "createFormat", at = @At(value = "INVOKE", target = "Lcom/mojang/renderpearl/api/vertex/VertexFormat$Builder;addAttribute(Ljava/lang/String;Lcom/mojang/renderpearl/api/GpuFormat;)Lcom/mojang/renderpearl/api/vertex/VertexFormat$Builder;"))
	private static VertexFormat.Builder lumen$addNeighbors(VertexFormat.Builder builder, String name, GpuFormat format, Operation<VertexFormat.Builder> original) {
		VertexFormat.Builder b = original.call(builder, name, format);
		if (BlockNeighborData.enabled && "at_midBlock".equals(name)) b = original.call(b, "at_neighbors", GpuFormat.RGBA32_UINT);
		return b;
	}
}
