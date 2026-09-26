import {interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

// Concept artwork only: actual ink, recognition and collaboration must come from the recorded clips.
export const FeatureVisual = ({id, active, stepSeconds = 0, stepDuration = 20}: {id: string; active: number; stepSeconds?: number; stepDuration?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const progress = interpolate(frame, [0.6 * fps, 2 * fps], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const arrow = `url(#arrow-${id})`;
  const brushHighlights = [[0, 1, 2, 3, 4], [2, 3], [1, 4], []][active] ?? [];
  const layoutUndo = active === 5 && stepSeconds < stepDuration / 2;
  const layoutRedo = active === 5 && !layoutUndo;
  return <svg viewBox="0 0 945 500" width="100%" height="100%" fill="none" aria-label="功能概念图，非应用界面">
    <defs>
      <marker id={`arrow-${id}`} markerWidth="16" markerHeight="16" refX="12" refY="8" orient="auto" markerUnits="userSpaceOnUse"><path d="M2 2 L12 8 L2 14 Z" fill="#171A18" /></marker>
    </defs>
    {id === 'library' && <>
      <path d="M85 358 L158 83 L501 43 L432 328 Z" fill="#D9DFD6" />
      <path d="M149 377 L205 79 L561 65 L509 363 Z" fill="#42DD91" />
      <g style={{translate: `0 ${24 * (1 - progress)}px`}}>
        <path d="M229 388 L262 112 L584 114 L568 391 Z" fill="#FFFFFF" stroke="#171A18" strokeWidth="2.5" />
        <text x="298" y="173" fill="#171A18" fontSize="42" fontWeight="700">二叉树</text>
        <path d="M407 224 L348 284 M407 224 L465 284 M348 284 L315 327 M348 284 L380 327" stroke="#171A18" strokeWidth="4" />
        {[{x: 407, y: 224}, {x: 348, y: 284}, {x: 465, y: 284}, {x: 315, y: 327}, {x: 380, y: 327}].map((node, i) => <circle key={i} cx={node.x} cy={node.y} r={i === 0 ? 16 : 12} fill={i === 0 ? '#42DD91' : '#171A18'} />)}
        <path d="M481 114 V168 L503 153 L525 168 V114" fill="#42DD91" />
      </g>
      <path d="M601 155 H715 M593 272 H715 M580 374 H715" stroke="#171A18" strokeWidth="4" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
      <text x="743" y="166" fill="#171A18" fontSize="32" fontWeight="700">PDF</text>
      <text x="743" y="283" fill="#087D5D" fontSize="32">标签</text>
      <text x="743" y="385" fill="#171A18" fontSize="32">分页</text>
    </>}
    {id === 'brushes' && <>
      {['圆珠笔', '钢笔', '铅笔', '毛笔', '荧光笔'].map((label, i) => <g key={label}>
        {brushHighlights.includes(i) && <rect x="9" y={49 + i * 83} width="120" height="40" fill="#42DD91" />}
        <text x="24" y={78 + i * 83} fill="#171A18" fontWeight={brushHighlights.includes(i) ? 700 : 400} fontSize="28">{label}</text>
      </g>)}
      <g strokeLinecap="round" strokeLinejoin="round">
        <path d="M171 69 C256 25 280 111 370 64 S502 20 575 67 S698 114 839 60" stroke="#171A18" strokeWidth="6" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
        <path d="M171 151 C244 111 263 192 352 149 S478 111 562 149 S697 193 839 143" stroke="#171A18" strokeWidth="12" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
        <path d="M171 233 C263 188 283 277 373 233 S506 191 583 233 S711 277 839 223" stroke="#526259" strokeWidth="7" strokeDasharray="2 3" opacity="0.85" />
        <path d="M171 233 C263 188 283 277 373 233 S506 191 583 233 S711 277 839 223" stroke="#526259" strokeWidth="3.5" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
        <path d="M165 320 C240 224 285 379 388 316 C477 261 513 275 565 313 C657 381 734 321 841 306 C714 357 659 376 555 330 C476 286 452 306 388 340 C270 390 253 250 165 320 Z" fill="#171A18" style={{clipPath: `inset(0 ${(1 - progress) * 100}% 0 0)`}} />
        <path d="M179 402 C325 384 430 401 546 402 S735 389 831 396" stroke="#42DD91" strokeWidth="38" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
      </g>
    </>}
    {id === 'recognition' && <>
      <path d="M72 171 C125 57 139 245 181 113 C199 58 195 208 236 126 C259 80 249 190 289 144" stroke="#171A18" strokeWidth="8" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
      <text x="153" y="229" fill="#58655E" fontSize="28" textAnchor="middle">笔迹</text>
      {[29, 52, 76, 44, 95, 67, 36, 72, 48].map((h, i) => <path key={i} d={`M${91 + i * 22} ${337 - h / 2} V${337 + h / 2}`} stroke="#087D5D" strokeWidth="5" strokeLinecap="round" opacity={progress} />)}
      <text x="178" y="437" fill="#58655E" fontSize="28" textAnchor="middle">语音</text>
      <path d="M315 147 H357 Q389 147 389 182 V252 H482 M315 337 H357 Q389 337 389 302 V252" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
      <path d="M521 112 H877 V365 H521 Z" fill="#FFFFFF" stroke="#D9DFD6" strokeWidth="3" />
      <path d="M548 318 H826" stroke="#42DD91" strokeWidth="20" />
      <text x="549" y="222" fill="#171A18" fontSize="61" fontWeight="700">二叉树</text>
      <text x="549" y="309" fill="#171A18" fontSize="61" fontWeight="700">复习要点</text>
      <path d="M820 253 V315" stroke="#087D5D" strokeWidth="4" />
      <text x="694" y="426" textAnchor="middle" fill="#087D5D" fontSize="28" letterSpacing="2">可编辑文本</text>
    </>}
    {id === 'layout' && <>
      {(active <= 2 || layoutUndo) && <g transform={`translate(${active === 2 ? 0 : 274} 0)`}>
        <rect x="45" y="48" width="344" height="397" fill="#FFFFFF" stroke="#D9DFD6" strokeWidth="2.5" />
        <path d="M64 97 L316 80 L327 128 L75 145 Z" stroke="#171A18" fill="#42DD9138" />
        <path d="M113 195 L340 229 M99 218 L326 252 M104 245 L297 273" stroke="#697870" strokeWidth="6" />
        <path d="M72 308 L214 290 L229 405 L88 426 Z" stroke="#087D5D" strokeWidth="3.5" fill="#42DD9138" />
        <path d="M149 326 L113 375 M149 326 L189 369" stroke="#171A18" strokeWidth="4" /><circle cx="149" cy="326" r="10" fill="#171A18" /><circle cx="113" cy="375" r="9" fill="#171A18" /><circle cx="189" cy="369" r="9" fill="#087D5D" />
        <path d="M262 328 L369 306 M263 353 L359 333 M268 378 L343 359" stroke="#171A18" strokeWidth="4" />
      </g>}
      {active === 1 && <>
        <path d="M328 64 H660 V438 H328 Z" stroke="#171A18" strokeWidth="3.5" strokeDasharray="8 10" />
        <path d={`M328 ${90 + interpolate(stepSeconds, [0, 2], [0, 320], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} H660`} stroke="#087D5D" strokeWidth="3.5" />
        <text x="700" y="129" fill="#171A18" fontSize="28">标题</text><text x="700" y="245" fill="#58655E" fontSize="28">正文</text><text x="700" y="359" fill="#087D5D" fontSize="28">图文关系</text>
      </>}
      {active === 2 && <path d="M401 252 H499" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} />}
      {active >= 2 && !layoutUndo && <g transform={`translate(${active === 2 ? 0 : -220} 0)`}>
        <rect x="543" y="61" width="311" height="360" fill="#FFFFFF" stroke="#171A18" strokeWidth="2.5" />
        <rect x="573" y="91" width="154" height="17" fill="#171A18" />
        <path d="M573 136 H821 M573 158 H821 M573 180 H782" stroke="#697870" strokeWidth="5" />
        <rect x="573" y="222" width="149" height="136" fill="#C8F5D8" />
        <path d="M649 249 L607 311 M649 249 L690 311" stroke="#171A18" strokeWidth="4" /><circle cx="649" cy="249" r="12" fill="#171A18" /><circle cx="607" cy="311" r="10" fill="#171A18" /><circle cx="690" cy="311" r="10" fill="#087D5D" />
        <path d="M746 240 H822 M746 263 H822 M746 286 H815" stroke="#697870" strokeWidth="5" />
        <path d="M573 389 H746" stroke="#171A18" strokeWidth="4" />
        {active === 3 && <><rect x="562" y="81" width="179" height="36" stroke="#087D5D" strokeWidth="3" strokeDasharray="7 5" /><rect x="562" y="213" width="171" height="155" stroke="#087D5D" strokeWidth="3" strokeDasharray="7 5" /></>}
      </g>}
      {active === 3 && <><path d="M527 99 H667 M514 286 H667" stroke="#171A18" strokeWidth="3.5" /><text x="687" y="109" fill="#171A18" fontSize="28">作为标题</text><text x="687" y="295" fill="#087D5D" fontSize="28">保留原件</text></>}
      {active >= 4 && !layoutUndo && <><circle cx="739" cy="241" r="44" fill="#42DD91" /><path d="M718 241 L734 258 L764 223" stroke="#171A18" strokeWidth="5" strokeLinecap="round" /></>}
      {layoutUndo && <path d="M754 280 C780 202 719 153 673 177 M673 177 L696 155 M673 177 L698 191" stroke="#171A18" strokeWidth="3" />}
      {active === 2 && <><text x="216" y="35" textAnchor="middle" fill="#58655E" fontSize="28">原稿</text><text x="699" y="35" textAnchor="middle" fill="#087D5D" fontSize="28">排版预览</text></>}
      {active >= 4 && <><text x="739" y="338" textAnchor="middle" fill="#171A18" fontSize="32" fontWeight="700">{layoutUndo ? '已撤销' : layoutRedo ? '已重做' : '已应用'}</text><text x="739" y="380" textAnchor="middle" fill="#087D5D" fontSize="28">{layoutUndo ? '原稿恢复' : layoutRedo ? '排版恢复' : '继续编辑'}</text></>}
    </>}
    {id === 'ai' && <>
      <g stroke="#171A18" strokeWidth="5" opacity={progress}>
        <path d="M255 160 H280 Q330 160 330 220 V249 H419" />
        <path d="M270 354 H280 Q330 354 330 294 V249" />
        <path d="M500 249 H568 Q603 249 603 214 V125 H701 M603 249 H729 M603 249 V370 H701" />
      </g>
      <rect x="75" y="76" width="176" height="153" fill="#FFFFFF" stroke="#D9DFD6" strokeWidth="3" />
      <path d="M162 112 L114 184 M162 112 L211 184" stroke="#171A18" strokeWidth="4" /><circle cx="162" cy="112" r="14" fill="#171A18" /><circle cx="114" cy="184" r="13" fill="#171A18" /><circle cx="211" cy="184" r="13" fill="#42DD91" />
      <text x="164" y="273" fill="#58655E" fontSize="28" textAnchor="middle">图示</text>
      <text x="87" y="369" fill="#171A18" fontSize="44" fontStyle="italic">O(log n)</text>
      <path d="M460 190 L519 249 L460 308 L401 249 Z" fill="#42DD91" /><text x="460" y="261" textAnchor="middle" fill="#171A18" fontSize="37" fontWeight="700">AI</text>
      {[{x: 755, y: 125, text: '理解'}, {x: 788, y: 249, text: '追问'}, {x: 755, y: 370, text: '导图'}].map((node, i) => <g key={node.text}>
        <circle cx={node.x} cy={node.y} r="51" fill={i === active ? '#171A18' : '#D5F8E5'} />
        <text x={node.x} y={node.y + 10} textAnchor="middle" fill={i === active ? '#42DD91' : '#171A18'} fontSize="28" fontWeight="700">{node.text}</text>
      </g>)}
    </>}
    {id === 'collab' && <>
      <path d="M231 89 L721 101 L710 416 L220 404 Z" fill="#D9DFD6" />
      <rect x="210" y="75" width="506" height="328" fill="#FFFFFF" stroke="#171A18" strokeWidth="2.5" />
      <path d="M250 157 H675 M250 246 H675 M250 335 H675" stroke="#D9DFD6" strokeWidth="2" />
      <text x="253" y="128" fill="#171A18" fontSize="31" fontWeight="700">同一页复习笔记</text>
      <path d="M365 187 L294 282 M365 187 L434 282" stroke="#171A18" strokeWidth="5" /><circle cx="365" cy="187" r="17" fill="#171A18" /><circle cx="294" cy="282" r="14" fill="#171A18" /><circle cx="434" cy="282" r="14" fill="#171A18" />
      <g opacity={active >= 3 ? .16 : 1}>
        <path d="M510 222 C536 175 551 279 581 220 S622 177 650 225 M505 295 C540 282 593 300 653 285" stroke="#087D5D" strokeWidth="7" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
        <path d="M502 330 H655" stroke="#42DD91" strokeWidth="25" />
      </g>
      <path d="M119 196 L190 234 M736 313 L804 269" stroke="#171A18" strokeWidth="4" />
      {[{x: 96, y: 178, label: 'A'}, {x: 829, y: 252, label: 'B'}].map((member, i) => <g key={member.label} opacity={active >= 3 && i > 0 ? .25 : 1}>
        <circle cx={member.x} cy={member.y} r="45" fill={i === 0 ? '#171A18' : '#42DD91'} />
        <text x={member.x} y={member.y + 12} textAnchor="middle" fontSize="36" fontWeight="700" fill={i === 0 ? '#F6F5F0' : '#171A18'}>{member.label}</text>
      </g>)}
      <path d="M255 184 L284 242 L265 240 L253 261 Z" fill="#171A18" />
      <path d="M665 247 L694 304 L676 302 L664 323 Z" fill="#087D5D" opacity={active >= 3 ? .2 : 1} />
      <text x="461" y="39" textAnchor="middle" fill="#087D5D" fontSize="27">{active >= 3 ? '仅当前视图聚焦' : '多人共创'}</text>
    </>}
    {id === 'openness' && <>
      <g stroke="#171A18" strokeWidth="4">
        <circle cx="158" cy="143" r="42" fill="#171A18" />
        <path d="M196 167 L244 214 M243 292 L185 335 M301 280 L351 331" />
        <rect x="229" y="212" width="80" height="80" transform="rotate(7 269 252)" fill="#42DD91" stroke="none" />
        <path d="M153 325 L191 389 L116 389 Z" fill="#171A18" />
        <circle cx="373" cy="359" r="34" fill="#FFFFFF" />
      </g>
      <path d="M417 222 H526" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
      <path d="M526 278 H417" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} pathLength="1" strokeDasharray="1" strokeDashoffset={1 - progress} />
      <rect x="588" y="85" width="280" height="318" fill="#171A18" />
      <text x="615" y="146" fill="#42DD91" fontSize="35" fontWeight="700">.markdraw</text>
      <path d="M622 193 H819 M622 226 H760 M648 258 H829 M648 290 H786 M622 323 H823 M622 356 H740" stroke="#F6F5F0" strokeWidth="6" />
      <text x="260" y="461" textAnchor="middle" fill="#087D5D" fontSize="29">画布</text>
      <text x="724" y="461" textAnchor="middle" fill="#171A18" fontSize="29">文本</text>
      <text x="471" y="343" textAnchor="middle" fill="#58655E" fontSize="26">双向同步</text>
    </>}
    {id === 'harmony' && <>
      <path d="M304 81 L609 64 L630 407 L325 424 Z" fill="#42DD91" />
      <rect x="323" y="79" width="276" height="348" rx="23" fill="#171A18" />
      <path d="M351 121 H571 V380 H351 Z" fill="#FFFFFF" stroke="#171A18" strokeWidth="2.5" />
      <path d="M391 229 C426 168 439 292 479 218 S532 187 535 233 M389 276 H529 M389 300 H494" stroke="#171A18" strokeWidth="5" strokeLinecap="round" />
      {active === 0 && <><path d="M122 173 H303" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} /><rect x="107" y="108" width="82" height="48" stroke="#087D5D" /><path d="M120 123 H173 M120 137 H156" stroke="#087D5D" strokeWidth="3" /><text x="104" y="229" fill="#171A18" fontSize="29">最近白板</text></>}
      {active === 1 && <><path d="M619 191 H745" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} /><circle cx="785" cy="156" r="22" stroke="#087D5D" strokeWidth="3.5" /><path d="M745 227 C745 179 825 179 825 227" stroke="#087D5D" strokeWidth="3.5" /><text x="728" y="294" fill="#087D5D" fontSize="29">设备身份</text></>}
      {active >= 2 && <><path d="M619 241 H725" stroke="#171A18" strokeWidth="3.5" markerEnd={arrow} />{['#171A18', '#42DD91', '#D9DFD6'].map((color, i) => <circle key={color} cx={747 + i * 49} cy="241" r="19" fill={color} />)}<text x="728" y="315" fill="#171A18" fontSize="29">取色落笔</text></>}
    </>}
  </svg>;
};
