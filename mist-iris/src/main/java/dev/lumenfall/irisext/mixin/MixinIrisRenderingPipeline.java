package dev.lumenfall.irisext.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import com.llamalad7.mixinextras.sugar.Local;
import dev.lumenfall.irisext.BlockNeighborData;
import dev.lumenfall.irisext.LumenPerf;
import dev.lumenfall.irisext.ShaderPropertiesExt;
import it.unimi.dsi.fastutil.ints.Int2IntMaps;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexType;
import net.irisshaders.iris.pipeline.IrisRenderingPipeline;
import net.irisshaders.iris.shaderpack.loading.ProgramId;
import net.irisshaders.iris.shaderpack.programs.ProgramSet;
import net.irisshaders.iris.shaderpack.programs.ProgramSource;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;

import java.util.List;
import java.util.Optional;

@Mixin(value = IrisRenderingPipeline.class, remap = false)
public class MixinIrisRenderingPipeline {
	@WrapOperation(method = "<init>", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/vertices/sodium/terrain/FormatAnalyzer;createFormat(ZZZZ)Lnet/caffeinemc/mods/sodium/client/render/chunk/vertex/format/ChunkVertexType;"))
	private ChunkVertexType lumen$neighbors(boolean blockId, boolean normal, boolean midUV, boolean midBlock, Operation<ChunkVertexType> original, @Local(argsOnly = true) ProgramSet programSet) {
		BlockNeighborData.enabled = lumen$usesNeighbors(programSet);
		Object props = ((ShaderPackAccessor) programSet.getPack()).lumen$properties();
		BlockNeighborData.groups = props instanceof ShaderPropertiesExt ext ? ext.lumen$neighborGroups() : Int2IntMaps.EMPTY_MAP;
		LumenPerf.configure(props instanceof ShaderPropertiesExt ext2 ? ext2.lumen$keys() : java.util.Map.of());
		return original.call(blockId, normal, midUV, midBlock);
	}

	@Unique
	private static boolean lumen$usesNeighbors(ProgramSet programSet) {
		for (ProgramId id : ProgramId.values()) {
			Optional<ProgramSource> source = programSet.get(id);
			if (source.isEmpty()) continue;
			for (Optional<String> stage : List.of(source.get().getVertexSource(), source.get().getGeometrySource(),
					source.get().getTessControlSource(), source.get().getTessEvalSource())) {
				if (stage.isPresent() && stage.get().contains("at_neighbors")) return true;
			}
		}
		return false;
	}
}
