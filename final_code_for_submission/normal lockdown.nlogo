;globals -----------------------------------------------------------------------------------
globals [cell-dimension collided pen show-turtles show-links time growth-factor oneday oneweek locked-cells weekday weekcount last-week-infected new-count-weekly-reset with-lockdown]
breed [humans human]
breed [hfs hf]
patches-own [ pid ]
humans-own [current-cell infection immunity recovery speed]
hfs-own [hf-id hf-infected-count last-week-new-infected local-growth-factor]
;-------------------------------------------------------------------------------------------




;basic setup and simulation loop ------------------------------------------------------------

to setup
  ;reset everything
  clear-all
  reset-ticks
  ask patches [
    set pcolor white
  ]
  set last-week-infected 0
  set new-count-weekly-reset true
  set weekday 0 ;1->7
  set weekcount 0
  set collided 0
  set pen false
  set with-lockdown true
  set show-turtles true
  set show-links false
  set time 0

  set cell-dimension ((max-pxcor + 1) / cell)
  set oneday (2 * (cell-dimension / 2))
;  set oneday 1
  set oneweek (7 * oneday)
  set locked-cells []

  DRAW-CELL-BORDERS
  DRAW-INFECTION

  SET-CELLS-ID
  BUILD-HFS

  POPULATE

  output-print "DONE SETTING UP!"
end

to go
  clear-output
  tick
  set weekday ((floor (ticks / oneday)) mod 7) + 1
  set weekcount (floor (ticks / oneweek))

  ask humans [
    if(color != green) [set pen-mode "down"]
    if(color != grey)
    [
      set heading (heading + (45 - random 90))

      let lastpatch [pid] of patch-here

      OUT-OF-BORDER
      FORWARD-WITHOUT-COLLISION
;      CELL-HAS-CHANGED lastpatch
      HUMAN-HEALTH
    ]
  ]

  ; compute growth factors and lockdown cells at the end of weekday 7
  if ((weekday = 7) and (((((ticks + 1) / oneday)) mod 7) = 0)) [

    ask hfs [
      set hf-infected-count 0
      if any? my-in-links [
        set hf-infected-count (count my-in-links)
      ]

      ; calculate growth factor by last week new infected/this week new infected
      ; if last week new infected = 0 then growth factor is 1
      (ifelse (last-week-new-infected = 0)
        [
          (ifelse (count my-in-links with [color = red] > 0)
            [
              set local-growth-factor 1
            ][
              set local-growth-factor 0
          ])
        ][
          set local-growth-factor ((count my-in-links with [color = red]) / last-week-new-infected)
      ])

      if(with-lockdown)[
        (ifelse(local-growth-factor >= 1)
          [
            LOCKDOWN-ON-CELL hf-id
          ][
            RELEASE-LOCKDOWN-ON-CELL hf-id
        ])
      ]

      set last-week-new-infected (count my-in-links with [color = red])
      ask my-in-links with [color = red] [set color 5]
    ]

    ; compute global growth factor
    let last-infected 0
    ask hfs [
      set last-infected (last-infected + last-week-new-infected)
    ]
    (ifelse(last-week-infected = 0)[
      set growth-factor 1
    ][
      set growth-factor (last-infected / last-week-infected)
    ])
    set last-week-infected last-infected


;    show "executed"
  ]



;  show weekday
end
;-------------------------------------------------------------------------------------------










;population creation ----------------------------------------------------------------------------------------

to POPULATE
  create-humans population [
    set color green
    set speed 1

    set infection 0
    set recovery 0
    set immunity (random (immune-system + 1))
    set immunity ((oneday * 5) + (oneday * (((10 - immunity) / 10) * 5))) ;set immunity to recovery-limit in ticks (5 days + 5 * immunity% days)

    PREVENT-BLOCK-SPAWN

    if ([pcolor] of patch-here = red) [ set color blue ]
  ]

;  ask n-of (population * 0.1) humans [set infection 1]
;  ask humans with [infection > 0] [set color grey]

end

to BUILD-HFS
  let cellx 0
  let celly 0
  let myid 0
  create-hfs (cell * cell) [
    let xrandom (random cell-dimension)
    let yrandom (random cell-dimension)
    setxy ((cell-dimension * cellx) + xrandom) ((cell-dimension * celly) + yrandom)

    while[([pcolor] of patch-here) = red]
    [
      set xrandom (random cell-dimension)
      set yrandom (random cell-dimension)
      setxy ((cell-dimension * cellx) + xrandom) ((cell-dimension * celly) + yrandom)
    ]

    ask patch-here
    [
      set myid pid
    ]
    set hf-id myid
    set shape "X"
    set color blue
    ask patches in-radius (hfs-radius) [
      if (pid = myid) [
        if (pcolor != red)[
           set pcolor rgb (145)(196)(255)
        ]
      ]
    ]
    set cellx (cellx + 1)
    if (cellx >= cell) [
      set celly (celly + 1)
      set cellx 0
    ]
  ]

end

to HUMAN-HEALTH
  let isNormal DETECT-INFECTION ;check if human isNormal (has no symptoms)
  let isRecovered DETECT-RECOVERY ;check if human is recovered after being infected
  let abnormaFirstDetected (DETECT-HEALTH-FACILITY self)
end

to PREVENT-BLOCK-SPAWN
  setxy random-xcor random-ycor
  if ([pcolor] of patch-here) = black
  [
    PREVENT-BLOCK-SPAWN
  ]
end

;-------------------------------------------------------------------------------------------








; population division getters ------------------------------------------------------------------

;report agent-set
to-report GET-SUSCEPTIBLE
  report (humans with [infection = 0])
end

;report agent-set
to-report GET-INFECTED
  report (humans with [infection > 0 and color != grey])
end

;report agent-set
to-report GET-RECOVERED
  report (humans with [color = grey])
end

;----------------------------------------------------------------------------------------------






;collision detection -------------------------------------------------------------------------------------------

to OUT-OF-BORDER
  let xh ([pxcor] of patch-here)
  let xa ([pxcor] of patch-ahead 1)
  let yh ([pycor] of patch-here)
  let ya ([pycor] of patch-ahead 1)
  if (xh = 0) and (xa = max-pxcor) [set heading (0 - heading)]
  if (xh = max-pxcor) and (xa = 0) [set heading (0 - heading)]
  if (yh = 0) and (ya = max-pycor) [set heading (180 - heading)]
  if (yh = max-pycor) and (ya = 0) [set heading (180 - heading)]
end

to FORWARD-WITHOUT-COLLISION
  let pfront (patch-ahead 1)
  let phere (patch-here)
  let xh ([pxcor] of phere)
  let yh ([pycor] of phere)
  let xf ([pxcor] of pfront)
  let yf ([pycor] of pfront)

  ;check if changing cells while inside a locked cell
  let locked-here ((member? ([pid] of phere) locked-cells) and (([pid] of pfront) != ([pid] of phere)))
  ;check if changing cells and stepping into a locked cell
  let locked-ahead ((member? ([pid] of pfront) locked-cells) and (([pid] of pfront) != ([pid] of phere)))

  ; change heading if facing an obstacle or changing cells when in lockdown
  ifelse ((([pcolor] of pfront) = black) or locked-here or locked-ahead)
  [
    ifelse ((xh - xf) != 0) and ((yh - yf) != 0)
    [
      set heading (0 - heading)
      if ([pcolor] of patch-ahead 1) = black [ set heading (180 - heading) ]
    ]
    [
      if ((xh - xf) = 0) [ set heading (180 - heading) ]
      if ((yh - yf) = 0) [ set heading (0 - heading) ]
    ]
  ]
  ; else if free to move then forward
  [
    forward speed
    set current-cell ([pid] of patch-here)
  ]
end

to-report DETECT-INFECTION
  ; increase infection by 1 if infection is greater than 0 and less than a week
  if (infection > 0) and (infection < (oneday * 7)) [set infection (infection + 1)]

  ; set infection when infected
  if (color = blue and infection = 0) [set infection 1]

  ; set infection to 1 when stepping on a red patch
  if (infection = 0) and (([pcolor] of patch-here) = red)
  [if(color != yellow) [ set color blue]]

  ; if not infected
  if(infection = 0)
  [
    ; check if humans nearby (with-infection-here) are infected
    let with-infection-here false
    ask humans-here
    [
      if (infection > 0 and color != grey)
      [
        set with-infection-here true
      ]
    ]

    ; if humans nearby are infected and randomized number is less than transmission-rate, set this human as infected
    if(with-infection-here = true) and (random 100 <= transmission-rate)
    [if(color != yellow) [ set color blue]]
  ]

  ; if infection value exceeds 7 days (a week) then show symptoms of this human
  if (infection >= (oneday * 7))
  [
    if color != yellow [set color yellow]
    report false
  ]

  report true
end

to-report DETECT-RECOVERY
  ; if human is showing infection symptoms then start recovery
  if(color = yellow)
  [
    ; set recovery counter
    if (recovery = 0) and (color = yellow) [set recovery 1]

    ; increment recovery when less than immunity
    if(recovery > 0) and (recovery < immunity) [ set recovery (recovery + 1)]

    ; change human status to recovered
    if(recovery >= immunity)
    [
      set color grey
;      ask my-out-links [die]
      report true
    ]
  ]

  if(color = grey)[report true]

  report false
end

to-report DETECT-HEALTH-FACILITY [current-human]
  ; current-human infected makes a link to the health facility when stepping at its radius
  let hfid ([pid] of patch-here)
  if((([pcolor] of patch-here) = [145 196 255]) and (([color] of current-human) = yellow) and (count my-out-links = 0))
  [
    ask hfs with [hf-id = hfid]
    [
      create-link-from current-human [set color red]
    ]
  ]

  report false
end

;to CELL-HAS-CHANGED [lastpatch]
;  if current-cell != lastpatch
;  [
;    ask my-out-links [die]
;    report true
;  ]
;  report false
;end

;-------------------------------------------------------------------------------------------










;setting cell ids ---------------------------------------------------------------------------------------

to SET-CELLS-ID
  let cell-id 1
  let x 0
  let y (cell - 1)
  repeat cell [
    repeat cell [
      SET-PATCH-ID (cell-dimension * (cell - cell + x)) (cell-dimension * (cell - cell + y)) cell-id
      set x (x + 1)
      set cell-id (cell-id + 1)
    ]
    set x 0
    set y (y - 1)
  ]
end

to SET-PATCH-ID [x y id]
  let row 0
  let col 0
  repeat cell-dimension [
    repeat cell-dimension [
      ask patch (col + x) (row + y) [
        set pid id
      ]
      set col (col + 1)
    ]
    set col 0
    set row (row + 1)
  ]
end

;-------------------------------------------------------------------------------------------







; setting/resetting lockdown ------------------------------------------------------------------

to LOCKDOWN-ON-CELL [cellid]
  if((member? cellid locked-cells) = false)
  [
    set locked-cells (fput cellid locked-cells)
;    DRAW-BORDER-ON-CELL cellid yellow
    ask hfs with [hf-id = cellid] [set color yellow]
  ]
end

to RELEASE-LOCKDOWN-ON-CELL [cellid]
  if(member? cellid locked-cells)
  [
    set locked-cells (remove-item (position cellid locked-cells) locked-cells)
;    DRAW-BORDER-ON-CELL cellid black
    ask hfs with [hf-id = cellid] [set color blue]
  ]
end


;---------------------------------------------------------------------------------------------







;Drawing borders -----------------------------------------------------------------------------------

to DRAW-BORDERS
  ask patches [
    sprout 1 [
      set color grey
      set heading 90
      forward 0.5
      set heading 0
      forward 0.5
      pen-down
      let angle 360
      repeat 4 [
        set angle (angle - 90)
        set heading angle
        forward 1
      ]
      die
    ]
  ]
end

to DRAW-CELL-BORDERS
  let row 0
  let column 0
  repeat cell [
    repeat cell [
      ask patch (cell-dimension - 1 + (row * cell-dimension)) (cell-dimension - 1 + (column * cell-dimension)) [
        sprout 1 [
          set color black
          set pen-size 5
          set heading 90
          forward 0.5
          set heading 0
          forward 0.5
          pen-down
          let angle 360
          repeat 4 [
            set angle (angle - 90)
            set heading angle
            forward cell-dimension
          ]
          die
        ]
      ]
      set column (column + 1)
    ]
    set row (row + 1)
  ]
end

to DRAW-INFECTION
  if infection-radius > 0
  [
    let origin (max-pxcor / 2)
    ask patch origin origin [
      sprout 1 [
        ask patches in-radius infection-radius [set pcolor red]
        die
      ]
    ]
  ]
end

;to DRAW-BORDER-ON-CELL [cellid bcolor]
;  let xcoor (remainder cellid cell)
;  if(xcoor = 0) [set xcoor cell]
;  let ycoor (ceiling (cellid / cell))
;  set xcoor ((xcoor - 1) * cell-dimension)
;  set ycoor (((cell - ycoor) * cell-dimension))
;  ask patch xcoor ycoor
;  [
;    sprout 1
;    [
;      set color bcolor
;      set pen-size 5
;      set heading 270
;      forward 0.5
;      set heading 180
;      forward 0.5
;      pen-down
;      let angle -90
;      repeat 4 [
;        set angle (angle + 90)
;        set heading angle
;        forward cell-dimension
;      ]
;      die
;    ]
;  ]
;end

;-------------------------------------------------------------------------------------------









;Drawing obstacles ------------------------------------------------------------------------------------------

to DRAW-CITY
  let block-dimension (cell-dimension / 8)
  let row 0
  let col 0
  let cell-col 0
  let cell-row [1 2 5 6]
  repeat cell [
    repeat cell [
      repeat cell-dimension [
        if ((cell-col mod 2) = 1) [
          foreach cell-row [x ->
            ask patch (col * cell-dimension + cell-col * block-dimension) (col * cell-dimension + x * block-dimension) [
              let i 0
              let j 0
              repeat block-dimension [
                repeat block-dimension [
                  ask patch-at i j [
                    set pcolor black
                  ]
                  set i (i + 1)
                ]
                set i 0
                set j (j + 1)
              ]
            ]
          ]
        ]
        set cell-col (cell-col + 1)
      ]
      set cell-col 0
      set col (col + 1)
    ]
    set row (row + 1)
  ]
end
;-------------------------------------------------------------------------------------------








;plotting ------------------------------------------------------------------------------------------
to PLOT-GLOBAL-GROWTH-FACTOR
  plotxy weekcount growth-factor
end

to PLOT-VS-POPULATION
  if count humans != 0
  [
    plotxy weekcount ((count humans with [color != grey])/(count humans))
  ]
end

to PLOT-S-HUMANS
  if count humans != 0
  [
    plotxy ticks (count GET-SUSCEPTIBLE / (count humans))
  ]
end

to PLOT-I-HUMANS
  if count humans != 0
  [
    plotxy ticks (count GET-INFECTED / (count humans))
  ]
end

to PLOT-R-HUMANS
  if count humans != 0
  [
    plotxy ticks (count GET-RECOVERED / count humans)
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
347
65
1355
1074
-1
-1
1.0
1
10
1
1
1
0
1
1
1
0
999
0
999
1
1
1
ticks
30.0

BUTTON
8
87
63
120
NIL
setup\n
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
82
88
137
121
go
reset-timer\n\n;if (((count humans with [color = grey])/(count humans)) <= 0.5)\n;if (((count humans with [color = grey])/(count humans)) < 1)\n;if ((count humans with [infection > 0 and color != grey]) > 0) or ((count humans with [color = grey]) = 0)\n;[\n; go\n; set time (timer + time)\n;]\n\nif (count GET-RECOVERED / count humans) < 0.5\n[\n go\n set time (timer + time)\n]
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

SLIDER
8
10
180
43
cell
cell
1
10
10.0
1
1
NIL
HORIZONTAL

INPUTBOX
186
10
250
70
population
3000.0
1
0
Number

SLIDER
8
46
180
79
immune-system
immune-system
0
10
10.0
1
1
NIL
HORIZONTAL

INPUTBOX
256
10
341
70
infection-radius
50.0
1
0
Number

OUTPUT
7
250
256
369
12

MONITOR
270
151
331
196
displayed?
pen
17
1
11

BUTTON
202
152
265
185
pen
ifelse not pen\n[\nask humans [pen-down]\nset pen true\n][\nask humans [pen-up]\nset pen false\n]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
148
88
219
121
+1g (space)
go
NIL
1
T
OBSERVER
NIL
Z
NIL
NIL
1

BUTTON
8
126
91
159
turtle-visibility
ifelse show-turtles\n[\nask turtles [hide-turtle]\nset show-turtles false\n]\n[\nask turtles [show-turtle]\nset show-turtles true\n]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
97
126
159
171
displayed?
show-turtles
17
1
11

PLOT
8
373
256
523
global growth factor
weekcount
growth-factor
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"pen-0" 1.0 0 -16777216 true "PLOT-GLOBAL-GROWTH-FACTOR" "PLOT-GLOBAL-GROWTH-FACTOR"

BUTTON
9
172
92
205
draw-patches
DRAW-BORDERS
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
170
205
266
238
link-visibility
ifelse show-links\n[\nask links [hide-link]\nset show-links false]\n[\nask links [show-link]\nset show-links true]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
271
205
342
250
displayed?
show-links
17
1
11

MONITOR
262
256
344
301
time elapsed
time
17
1
11

INPUTBOX
244
80
341
140
transmission-rate
20.0
1
0
Number

INPUTBOX
265
309
342
369
hfs-radius
25.0
1
0
Number

PLOT
8
533
255
712
sir
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -13840069 true "" "PLOT-S-HUMANS"
"pen-1" 1.0 0 -7500403 true "" "PLOT-R-HUMANS"
"pen-2" 1.0 0 -2674135 true "" "PLOT-I-HUMANS"

MONITOR
267
376
340
421
NIL
weekcount
17
1
11

BUTTON
9
214
91
247
lockdown
set with-lockdown not with-lockdown
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
78
204
170
249
NIL
with-lockdown
17
1
11

MONITOR
347
10
1328
55
NIL
locked-cells
17
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
