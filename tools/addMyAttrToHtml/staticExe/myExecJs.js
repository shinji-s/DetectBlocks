function writePos() {
    var elemarr = new Array();
    elemarr.push(document.body);
    while(elemarr.length > 0){
	var elem = elemarr.shift();
	if(elem.nodeType == 1){
	    //offsetParentも考慮して絶対位置にする。
	    if(parent = elem.offsetParent){
		elem.setAttribute("myTop", (elem.offsetTop-0) + (parent.getAttribute("myTop")-0));
		elem.setAttribute("myLeft", (elem.offsetLeft-0) + (parent.getAttribute("myLeft")-0));
		elem.setAttribute("myHeight", elem.offsetHeight);
		elem.setAttribute("myWidth", elem.offsetWidth);
	    }else{
		elem.setAttribute("myTop",elem.offsetTop);
		elem.setAttribute("myLeft",elem.offsetLeft);
		elem.setAttribute("myHeight",elem.offsetHeight);
		elem.setAttribute("myWidth",elem.offsetWidth);
	    }
	}

	var computedStyle = document.defaultView.getComputedStyle(elem, "");
	// 背景色を得る
	if(backgroundColor = computedStyle.backgroundColor){
	    elem.setAttribute("myBackgroundColor", backgroundColor);
	}
	// 枠線を得る
	if(borderColor = computedStyle.borderColor){
	    elem.setAttribute("myBorderColor", borderColor);
	}
	// フォントサイズを得る
	// 子供にテキストノードがある場合のみ
	for(i=0; i<elem.childNodes.length; i++){
	    if(elem.childNodes[i].nodeType == 3){
		if(fontSize = computedStyle.fontSize){
		    elem.setAttribute("myFontSize", fontSize);
		    break;
		}
	    }
	}
	// hiddenの場合はフラグを立てる
	if ( computedStyle.visibility == "hidden" || computedStyle.display == "none" ) {
	    elem.setAttribute("myHidden", 1);
	}

	for(i=0; i<elem.childNodes.length; i++){
	    if(elem.childNodes[i].nodeType == 1){
		elemarr.push(elem.childNodes[i]);
	    }
	}
    }
}

writePos();