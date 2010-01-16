// Generate a fantasy-world map
// Author: amitp@cs.stanford.edu
// License: MIT

// TODO:
// 1. break up generation into stages (low res, then high res, then wind)
// 2. link stages to onEnterFrame so that the system isn't unresponsive
// 3. make lighting size-independent
// 4. make blurring optional

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.filters.*;
  import flash.text.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.net.*;

  public class mapgen extends Sprite {
    public static var SEED:int = 72689;
    // 83980, 59695, 94400, 92697, 30628, 9146, 23896, 60489, 57078, 89680, 10377, 42612, 29732
    public static var OCEAN_ALTITUDE:int = 1;
    public static var SIZE:int = 256;
    public static var BIGSIZE:int = 2048;
    public static var DETAILSIZE:int = 64;

    public var seed_text:TextField = new TextField();
    public var seed_button:TextField = new TextField();
    public var save_altitude_button:TextField = new TextField();
    public var save_moisture_button:TextField = new TextField();
    public var location_text:TextField = new TextField();
    public var moisture_iterations:TextField = new TextField();
    public var generate_button:TextField = new TextField();
    
    public var altitude:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
    public var moisture:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
    public var rivers:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
    
    public var map:BitmapData = new BitmapData(SIZE, SIZE);
    public var lightingMap:BitmapData = new BitmapData(SIZE, SIZE);
    public var detailMap:BitmapData = new BitmapData(DETAILSIZE, DETAILSIZE);
    public var moistureBitmap:BitmapData = new BitmapData(SIZE, SIZE);
    public var altitudeBitmap:BitmapData = new BitmapData(SIZE, SIZE);
    
    public function mapgen() {
      stage.scaleMode = "noScale";
      stage.align = "TL";
      
      addChild(new Debug(this));
      
      graphics.beginFill(0x9999aa);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      function createLabel(text:String, x:int, y:int):TextField {
        var t:TextField = new TextField();
        t.text = text;
        t.width = 0;
        t.x = x;
        t.y = y;
        t.autoSize = TextFieldAutoSize.RIGHT;
        t.selectable = false;
        return t;
      }
      
      function changeIntoEditable(field:TextField, text:String):void {
        field.text = text;
        field.background = true;
        field.autoSize = TextFieldAutoSize.LEFT;
        field.type = TextFieldType.INPUT;
      }
      
      function changeIntoButton(button:TextField, text:String):void {
        button.text = text;
        button.background = true;
        button.selectable = false;
        button.autoSize = TextFieldAutoSize.LEFT;
        button.filters = [new BevelFilter(1)];
      }

      changeIntoEditable(seed_text, "" + SEED);
      seed_text.restrict = "0-9";
      seed_text.x = 180;
      seed_text.y = 50;
      addChild(seed_text);
      addChild(createLabel("Seed:", 180, 50));
               
      changeIntoEditable(moisture_iterations, "6");
      moisture_iterations.restrict = "0-9";
      moisture_iterations.x = 180;
      moisture_iterations.y = 80;
      addChild(moisture_iterations);
      addChild(createLabel("Wind iter:", 180, 80));

      changeIntoButton(generate_button, " Update ");
      generate_button.x = 160;
      generate_button.y = 120;
      generate_button.addEventListener(MouseEvent.MOUSE_UP,
                                       function (e:Event):void {
                                         SEED = int(seed_text.text);
                                         newMap();
                                       });
      addChild(generate_button);

      changeIntoButton(seed_button, " Random seed ");
      seed_button.x = 160;
      seed_button.y = 160;
      seed_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     SEED = int(100000*Math.random());
                                     seed_text.text = "" + SEED;
                                     newMap();
                                   });
      addChild(seed_button);

      changeIntoButton(save_altitude_button, " Export Altitude ");
      save_altitude_button.x = 160;
      save_altitude_button.y = 220;
      save_altitude_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     saveAltitudeMap();
                                   });
      addChild(save_altitude_button);

      changeIntoButton(save_moisture_button, " Export Moisture ");
      save_moisture_button.x = 160;
      save_moisture_button.y = 240;
      save_moisture_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     saveMoistureMap();
                                   });
      addChild(save_moisture_button);

      b = new Bitmap(moistureBitmap);
      b.x = 0;
      b.y = 20;
      b.scaleX = 128.0/SIZE;
      b.scaleY = b.scaleX;
      addChild(b);

      b = new Bitmap(altitudeBitmap);
      b.x = 0;
      b.y = 150;
      b.scaleX = 128.0/SIZE;
      b.scaleY = b.scaleX;
      addChild(b);

      // NOTE: Bitmap and Shape objects do not support mouse events,
      // so I'm wrapping the bitmap inside a sprite.
      var s:Sprite = new Sprite();
      s.x = 0;
      s.y = 270;
      s.scaleX = s.scaleY = 256.0/SIZE;
      s.addEventListener(MouseEvent.MOUSE_DOWN,
                         function (e:MouseEvent):void {
                           s.addEventListener(MouseEvent.MOUSE_MOVE, onMapClick);
                           onMapClick(e);
                         });
      stage.addEventListener(MouseEvent.MOUSE_UP,
                             function (e:MouseEvent):void {
                               s.removeEventListener(MouseEvent.MOUSE_MOVE, onMapClick);
                             });
        
      s.addChild(new Bitmap(map));
      s.addChild(new Bitmap(lightingMap)).blendMode = BlendMode.HARDLIGHT;
      addChild(s);

      location_text.text = "(detail map) ==>";
      location_text.x = 150;
      location_text.y = 200;
      location_text.autoSize = TextFieldAutoSize.LEFT;
      addChild(location_text);

      var b:Bitmap = new Bitmap(detailMap);
      b.x = 260;
      b.y = 0;
      b.scaleX = 512.0 / DETAILSIZE;
      b.scaleY = 512.0 / DETAILSIZE;
      addChild(b);
      
      newMap();
    }

    public function saveAltitudeMap():void {
      // Save the altitude minimap (not the big map, where we don't have altitude)
      new FileReference().save(flattenArray(altitude));
    }

    public function saveMoistureMap():void {
      // Save the moisture minimap (not the big map)
      new FileReference().save(flattenArray(moisture));
    }

    public function flattenArray(A:Vector.<Vector.<int>>):ByteArray {
      var B:ByteArray = new ByteArray();
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          B.writeByte(A[x][y]);
        }
      }
      return B;
    }
    
    public function onMapClick(event:MouseEvent):void {
      location_text.text = "" + event.localX + ", " + event.localY;
      generateDetailMap(event.localX, event.localY);
    }

    public function newMap():void {
      location_text.text = "(generating)";
      generate();
     
      //carveCanyons();

      for (var i:int = 0; i < int(moisture_iterations.text); i++) {
        spreadMoisture();
        //blurMoisture();
      }
     
      channelsToColors();
      channelsToLighting();
      arrayToBitmap(moisture, moistureBitmap);
      arrayToBitmap(altitude, altitudeBitmap);
      location_text.text = "";
    }
    
    public function generate():void {
      // Generate 3-channel perlin noise and copy 2 of the channels out
      var b:BitmapData = new BitmapData(SIZE, SIZE);
      b.perlinNoise(SIZE, SIZE, 8, SEED, false, false);

      equalizeTerrain(b);
      
      var s:Shape = new Shape();

      var m:Matrix = new Matrix();
      m.createGradientBox(SIZE, SIZE, 0, 0, 0);
      s.graphics.beginGradientFill(GradientType.RADIAL,
                                   [0x000000, 0x000000],
                                   [0.0, 0.2],
                                   [0x00, 0xff],
                                   m,
                                   SpreadMethod.PAD);
      s.graphics.drawRect(0, 0, SIZE, SIZE);
      s.graphics.endFill();
      b.draw(s);

      s.graphics.clear();
      s.graphics.beginFill(0xffffff, 0.2);
      s.graphics.drawRect(10, 10, SIZE-2*10, SIZE-2*10);
      s.graphics.endFill();
      b.draw(s);
      
      equalizeTerrain(b);

      
      // Extract information from bitmap
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          var c:int = b.getPixel(x, y);
          altitude[x][y] = (c >> 8) & 0xff;
          moisture[x][y] = c & 0xff;
        }
      }
    }

    public function equalizeTerrain(b:BitmapData):void {
      // Adjust altitude histogram so that it's roughly quadratic
      var histograms:Vector.<Vector.<Number>> = b.histogram(b.rect);
      var A:Vector.<Number> = histograms[1];
      var k:int = 0;
      var green:Array = new Array(256);
      var cumsum:Number = 0.0;
      for (var i:int = 0; i < 256; i++) {
        cumsum += A[i];
        green[i] = (k*k/256) << 8; // int to green color value
        while (cumsum > SIZE*SIZE*Math.sqrt(k/256.0) && k < 255) {
          k++;
        }
      }
      b.paletteMap(b, b.rect, new Point(0, 0), null, green, null, null);
      
      // Blur everything because the quadratic shift introduces
      // discreteness -- ick!!  TODO: probably better to apply the
      // histogram correction after we convert to the altitude[]
      // array, although even there it's already been discretized :(
      b.applyFilter(b, b.rect, new Point(0, 0), new BlurFilter());
    }
    
    public function make2dArray(w:int, h:int):Vector.<Vector.<int>> {
      var v:Vector.<Vector.<int>> = new Vector.<Vector.<int>>(w);
      for (var x:int = 0; x < w; x++) {
        v[x] = new Vector.<int>(h);
        for (var y:int = 0; y < h; y++) {
          v[x][y] = 0;
        }
      }
      return v;
    }

    public function arrayToBitmap(v:Vector.<Vector.<int>>, b:BitmapData):void {
      b.lock();
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          var c:int = v[x][y];
          b.setPixel(x, y, (c << 16) | (c << 8) | c);
        }
      }
      b.unlock();
    }

    public function blurMoisture():void {
      // Note: this isn't scale-independent :(
      var radius:int = 1;
      var result:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
      
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          var numer:int = 0;
          var denom:int = 0;
          for (var dx:int = -radius; dx <= +radius; dx++) {
            for (var dy:int = -radius; dy <= +radius; dy++) {
              if (0 <= x+dx && x+dx < SIZE && 0 <= y+dy && y+dy < SIZE) {
                numer += moisture[x+dx][y+dy];
                denom += 1;
              }
            }
          }
          result[x][y] = numer / denom;
        }
      }
      moisture = result;
    }
    
    public function spreadMoisture():void {
      var windX:Number = 250.0 * SIZE/BIGSIZE;
      var windY:Number = 120.0 * SIZE/BIGSIZE;

      var result:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          if (altitude[x][y] < OCEAN_ALTITUDE) {
            result[x][y] += 255; // ocean
          }
          
          result[x][y] += moisture[x][y];

          var wx:Number = 0.1 * (8.0 + Math.random() + Math.random());
          var wy:Number = 0.1 * (8.0 + Math.random() + Math.random());
          var x2:int = x + int(windX * wx);
          var y2:int = y + int(windY * wy);
          x2 %= SIZE; y2 %= SIZE;
          if (0 <= x2 && x2 < SIZE
              && 0 <= y2 && y2 < SIZE
              && x != x2 && y != y2) {
            var transfer:int = moisture[x][y]/3;
            var speed:Number = (30.0 + altitude[x][y]) / (30.0 + altitude[x2][y2]);
            if (speed > 1.0) speed = 1.0;
            /* speed is lower if going uphill */
            transfer = int(transfer * speed);
            
            result[x][y] -= transfer;
            result[x2][y2] += transfer;
          }
        }
      }

      for (x = 0; x < SIZE; x++) {
        for (y = 0; y < SIZE; y++) {
          if (result[x][y] < 0) result[x][y] = 0;
          if (result[x][y] > 255) result[x][y] = 255;
        }
      }
      
      moisture = result;
    }

    public function carveCanyons():void {
      for (var iteration:int = 0; iteration < 10000; iteration++) {
        var x:int = int(Math.floor(SIZE*Math.random()));
        var y:int = int(Math.floor(SIZE*Math.random()));

        for (var trail:int = 0; trail < 1000; trail++) {
          // Just quit at the boundaries
          if (x == 0 || x == SIZE-1 || y == 0 || y == SIZE-1) {
            break;
          }

          // Find the minimum neighbor
          var x2:int = x, y2:int = y;
          for (var dx:int = -1; dx <= +1; dx++) {
            for (var dy:int = -1; dy <= +1; dy++) {
              if (altitude[x+dx][y+dy] < altitude[x2][y2]) {
                x2 = x+dx; y2 = y+dy;
              }
            }
          }

          // TODO: make the river keep going to the ocean no matter what!
          
          // Move the particle in that direction, and remove some land
          if (x == x2 && y == y2) {
            if (altitude[x][y] < 10) break;
            // altitude[x][y] = Math.min(255, altitude[x][y] + trail);
          }
          x = x2; y = y2;
          altitude[x][y] = Math.max(0, altitude[x][y] - 1);
          rivers[x][y] += 1;
        }
      }

      for (x = 0; x < SIZE; x++) {
        for (y = 0; y < SIZE; y++) {
          if (rivers[x][y] > 100) moisture[x][y] = 255;
        }
      }
    }

    public function moistureAndAltitudeToColor(m:Number, a:Number, r:Number):int {
      var color:int = 0xff0000;
      
      if (a < OCEAN_ALTITUDE) color = 0x000099;
      else if (a < OCEAN_ALTITUDE + 3) color = 0xc2bd8c;
      else if (a < OCEAN_ALTITUDE + 5) color = 0xae8c4c;
      else if (a > 220) {
        if (a > 250) color = 0xffffff;
        else if (a > 240) color = 0xeeeeee;
        else if (a > 230) color = 0xddddcc;
        else color = 0xccccaa;
        if (m > 150) color -= 0x331100;
      }

      else if (r > 10) color = 0x00cccc;

      else if (m > 200) color = 0x56821b;
      else if (m > 150) color = 0x3b8c43;
      else if (m > 100)  color = 0x54653c;
      else if (m > 50)  color = 0x334021;
      else if (m > 20)  color = 0x989a2d;
      else              color = 0xc2bd8c;
      
      return color;
    }
    
    public function channelsToColors():void {
      map.lock();
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          map.setPixel(x, y, moistureAndAltitudeToColor(moisture[x][y],
                                                        altitude[x][y] - (x+y)%2,
                                                        rivers[x][y]));
        }
      }
      map.unlock();
    }

    public function channelsToLighting():void {
      // From the altitude map, generate a light map that highlights
      // northwest sides of hills. Then blur it all to remove sharp edges.
      lightingMap.lock();
      arrayToBitmap(altitude, lightingMap);
      // NOTE: the scale for the lighting should be changed depending
      // on the map size but it's not clear in what way. Alternatively
      // we could rescale the lightingMap to a fixed size and always
      // use that for lighting.
      lightingMap.applyFilter(lightingMap, lightingMap.rect, new Point(0, 0),
                              new ConvolutionFilter
                              (3, 3, [-2, -1, 0,
                                      -1, 0, +1,
                                      0, +1, +2], 3.0, 127));
      lightingMap.applyFilter(lightingMap, lightingMap.rect, new Point(0, 0),
                              new BlurFilter());
      lightingMap.unlock();
    }

    public function generateDetailMap(centerX:Number, centerY:Number):void {
      var NOISESIZE:int = 70;
      var noise:BitmapData = new BitmapData(NOISESIZE, NOISESIZE);
      var noiseScale:int = 1; // out of 128
      noise.noise(SEED, 128-noiseScale, 128+noiseScale);

      // We want to fill an area DETAILSIZE x DETAILSIZE by combining
      // the base moisture and altitude levels with the noise function
      // (deterministic, since we use a non-random seed).

      // Coordinates of the top left of the detail area:
      var baseX:int = int(centerX * BIGSIZE/SIZE - DETAILSIZE/2);
      var baseY:int = int(centerY * BIGSIZE/SIZE - DETAILSIZE/2);

      // 4-point interpolation function
      function interpolate(A:Vector.<Vector.<int>>, x:Number, y:Number):Number {
        var coarseX:int = int(Math.floor(x));
        var coarseY:int = int(Math.floor(y));
        var fracX:Number = x - coarseX;
        var fracY:Number = y - coarseY;

        return (A[coarseX][coarseY] * (1-fracX) * (1-fracY)
                + A[coarseX+1][coarseY] * fracX * (1-fracY)
                + A[coarseX][coarseY+1] * (1-fracX) * fracY
                + A[coarseX+1][coarseY+1] * fracX * fracY);
      }
      
      // Go through the detail area and compute each pixel color
      for (var x:int = baseX; x < baseX + DETAILSIZE; x++) {
        for (var y:int = baseY; y < baseY + DETAILSIZE; y++) {
          // The moisture and altitude at x,y will be based on the
          // coarse map, plus the noise scaled by some constant

          var noiseColor:int = noise.getPixel(x % NOISESIZE, y % NOISESIZE);

          var m:Number = interpolate(moisture, x * SIZE/BIGSIZE, y * SIZE/BIGSIZE) + ((noiseColor & 0xff) - 128);
          var a:Number = interpolate(altitude, x * SIZE/BIGSIZE, y * SIZE/BIGSIZE);

          // Make sure that the noise never turns ocean into non-ocean or vice versa
          if (a >= OCEAN_ALTITUDE) {
            a += (((noiseColor >> 8) & 0xff) - 128);
            if (a < OCEAN_ALTITUDE) {
              a = OCEAN_ALTITUDE;
            }
          }
          
          detailMap.setPixel(x - baseX, y - baseY,
                             moistureAndAltitudeToColor(m, a, 0));
        }
      }
    }
  }
}
