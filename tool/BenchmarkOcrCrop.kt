package com.local.shorts_studio

import android.graphics.Bitmap
import android.graphics.Rect
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/** Detect text across the actual frame, then select an OCR-free area.
 * Never claim text was removed by a fixed crop or by synthetic inpainting. */
object BenchmarkOcrCrop {
    data class Region(val x:Int,val y:Int,val w:Int,val h:Int,
        val detected:Int,val areaScore:Double){
        fun normalized(width:Int,height:Int):Map<String,Double> = mapOf(
            "x" to x.toDouble()/width,"y" to y.toDouble()/height,
            "w" to w.toDouble()/width,"h" to h.toDouble()/height)
    }

    fun newRecognizer():TextRecognizer =
        TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())

    /** Single-character reaction subtitles count as text too.
     * The first scan is made on the whole scene, the second on a zoomed crop.
     * An OCR miss can still happen, so this is a conservative filter, not
     * proof that the image contains absolutely no lettering.
     */
    private fun findTextBoxes(frame:Bitmap,recognizer:TextRecognizer):List<Rect>{
        val output=Tasks.await(
            recognizer.process(InputImage.fromBitmap(frame,0)),
            7,TimeUnit.SECONDS)
        val result=mutableListOf<Rect>()
        for(block in output.textBlocks) for(line in block.lines){
            if(!line.text.any{it.isLetterOrDigit()})continue
            val rect=line.boundingBox?:continue
            // Include the colored glow/outline around subtitles and
            // clipped edge characters, which OCR sometimes bounds too tightly.
            val dx=maxOf(12,frame.width/26)
            val dy=maxOf(12,frame.height/34)
            result.add(Rect((rect.left-dx).coerceAtLeast(0),
                (rect.top-dy).coerceAtLeast(0),
                (rect.right+dx).coerceAtMost(frame.width),
                (rect.bottom+dy).coerceAtMost(frame.height)))
        }
        return result
    }

    fun select(frame:Bitmap,recognizer:TextRecognizer):Region?{
        // Do not silently accept a frame if either OCR pass fails.
        val boxes=findTextBoxes(frame,recognizer)
        val width=frame.width;val height=frame.height
        val possibilities=mutableListOf<Region>()
        val seen=mutableSetOf<String>()
        for(fw in listOf(.94,.90,.84,.76,.66,.60))
            for(fh in listOf(.68,.61,.54,.47,.39,.31,.25)){
            if(fw*fh<.18)continue
            val cw=(width*fw).toInt();val ch=(height*fh).toInt()
            if(cw<130||ch<90)continue
            for(cx in listOf(.5,.42,.58))
                for(cy in listOf(.30,.40,.50,.60,.70)){
                val x=(width*cx-cw/2).toInt().coerceIn(0,width-cw)
                val y=(height*cy-ch/2).toInt().coerceIn(0,height-ch)
                val rect=Rect(x,y,x+cw,y+ch)
                if(boxes.any{Rect.intersects(it,rect)})continue
                if(!seen.add("$x:$y:$cw:$ch"))continue
                val score=fw*fh*10+(1.0-abs(cy-.50))
                possibilities.add(Region(x,y,cw,ch,boxes.size,score))
            }
        }
        // Only recheck the largest OCR-free alternatives; bound processing.
        val ordered=possibilities.sortedByDescending{it.areaScore}.take(8)
        for(region in ordered){
            val crop=Bitmap.createBitmap(frame,region.x,region.y,region.w,region.h)
            try{
                // Upscaling makes small, partially clipped caption letters
                // more visible to the secondary recognizer.
                val maxEdge=maxOf(crop.width,crop.height)
                val multiplier=if(maxEdge<1000)2 else 1
                val scaled=if(multiplier>1)Bitmap.createScaledBitmap(crop,
                    crop.width*multiplier,crop.height*multiplier,true)else crop
                try{
                    if(findTextBoxes(scaled,recognizer).isEmpty())return region
                }finally{
                    if(scaled!==crop)scaled.recycle()
                }
            }finally{crop.recycle()}
        }
        return null
    }
}
