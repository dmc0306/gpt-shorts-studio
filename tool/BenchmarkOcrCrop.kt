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

    fun select(frame:Bitmap,recognizer:TextRecognizer):Region?{
        val detected=Tasks.await(recognizer.process(InputImage.fromBitmap(frame,0)),
            7,TimeUnit.SECONDS)
        val boxes=mutableListOf<Rect>()
        for(block in detected.textBlocks) for(line in block.lines){
            if(line.text.count{it.isLetterOrDigit()}<2)continue
            val bounds=line.boundingBox?:continue
            val dx=maxOf(6,frame.width/45);val dy=maxOf(5,frame.height/65)
            boxes.add(Rect((bounds.left-dx).coerceAtLeast(0),
                (bounds.top-dy).coerceAtLeast(0),
                (bounds.right+dx).coerceAtMost(frame.width),
                (bounds.bottom+dy).coerceAtMost(frame.height)))
        }
        val width=frame.width;val height=frame.height
        var best:Region?=null
        // Try wider/taller windows first (up to 94% x 68% of the frame) while
        // strictly rejecting every OCR-intersecting window. Never expand
        // across detected captions to make the search look more inclusive.
        // Search multiple aspect/height positions, rather than crop the same
        // top/bottom proportion regardless of where the editor puts subtitles.
        for(fw in listOf(.94,.90,.84,.76,.66)) for(fh in listOf(.68,.61,.54,.47,.39,.31)){
            if(fw*fh<.20)continue
            val cw=(width*fw).toInt();val ch=(height*fh).toInt()
            if(cw<130||ch<90)continue
            for(cx in listOf(.5,.42,.58)) for(cy in listOf(.30,.40,.50,.60,.70)){
                val x=(width*cx-cw/2).toInt().coerceIn(0,width-cw)
                val y=(height*cy-ch/2).toInt().coerceIn(0,height-ch)
                val rect=Rect(x,y,x+cw,y+ch)
                if(boxes.any{Rect.intersects(it,rect)})continue
                val score=fw*fh*10+(1.0-abs(cy-.50))
                if(best==null||score>best!!.areaScore)
                    best=Region(x,y,cw,ch,boxes.size,score)
            }
        }
        return best
    }
}
