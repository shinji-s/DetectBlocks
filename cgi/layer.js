// myblocktype属性を持つエレメントに半透明のレイヤーをかぶせる
// 色はgetMyBlockTypeColorで指定している


document.getElementsByAttribute = function(name, val, elm) {
	var result = [];
	var e;
	if(typeof elm == "string") {
		e = document.getElementById(elm);
	} else if(elm.nodeType == 1){
		e = elm;
	}else {
		return [];
	}	

	if(val != "") {
		if(e.getAttribute(name) == val) {
			result.push(e);
		}
	} else {
		if(e.getAttribute(name) != undefined) {
			result.push(e);
		}
	}
	
	if(e.hasChildNodes()) {
		for(var i = 0; i < e.childNodes.length; i++){
			var reList = document.getElementsByAttribute(name, val, e.childNodes[i]);
			for (var j = 0; j< reList.length; j++) {
				if (reList[j].nodeType == 1) {
					result.push(reList[j]);
				}
			}
		}
	}
	return result;
};


document.getValuesByAttribute = function(name, val, elm) {
	var result = [];
	var e;
	if(typeof elm == "string") {
		e = document.getElementById(elm);
	} else if(elm.nodeType == 1){
		e = elm;
	}else {
		return [];
	}	

	if(val == "") {
		if(e.getAttribute(name) != undefined) {
			result.push(e.getAttribute(name));
		}
	} else {
		return [];
	}
	
	if(e.hasChildNodes()) {
		for(var i = 0; i < e.childNodes.length; i++){
			var reList = document.getValuesByAttribute(name, val, e.childNodes[i]);
			for (var j = 0; j< reList.length; j++) {
				result.push(reList[j]);
			}
		}
	}

	return result;
};


function FloatLayer() {
	this.initialize.apply(this, arguments);
};



FloatLayer.prototype = {

	initialize:function () {},

// 位置や大きさを指定してレイヤーをかぶせる
	addLayer:function (top, left, width, height, color, id, borderStyle) {
		var container = document.createElement("div");
		container.setAttribute("id", id);
		container.style.margin = "0px";
		container.style.padding = "0px";
		container.style.background = "none";
		document.body.appendChild(container);

		container.style.width = width + "px";
		container.style.height = height + "px";
		container.style.position = "absolute";
		container.style.left = left + "px";
		container.style.top = top + "px";
		container.style.background = color;
		container.style.opacity = "0.6";
		container.style.zIndex = "10000";
		container.style.borderStyle = borderStyle;
	},

// エレメントにレイヤーをかぶせる
	addOverNode:function (elem, color, Id) {
		var tmpElem = elem;
		var position = this.getAbsolutePosition(tmpElem);

		this.addLayer(position["top"], position["left"], position["width"], 
				position["height"], color, Id, "double");
	},

	addSeparator:function (elem, color, Id) {
		var tmpElem = elem;
                var offsetTop = elem.getAttribute('myOffsetTop');
                var offsetLeft = elem.getAttribute('myOffsetLeft');
                var offsetWidth = elem.getAttribute('myOffsetWidth');
                var offsetHeight = elem.getAttribute('myOffsetHeight');

		if (offsetWidth == 0) {
			offsetLeft -= 1; offsetWidth = 2;
		}
		if (offsetHeight == 0) {
			offsetTop -= 1; offsetHeight = 2;
		}

                this.addLayer(offsetTop, offsetLeft, offsetWidth, offsetHeight, color, Id, "none");
	},

	dynamicAddSeparator:function (elem, color, Id) {
		var tmpElem = elem;

		if ((tmpId = elem.getAttribute('separateBlock1')) != -1) {
			var sepBlock1 = document.getElementsByAttribute('myBlockId', tmpId, document.body)[0];
			var position1 = this.getAbsolutePosition(sepBlock1);
	                var block1Top = position1["top"];
        	        var block1Left = position1["left"];
			var block1Width = position1["width"];
			var block1Height = position1["height"];
                	var block1Bottom = block1Top + block1Height;
                	var block1Right = block1Left + block1Width;
		} else {
	                var block1Top = 0;
        	        var block1Left = 0;
			var block1Widht = 0;
			var block1Height = 0;
                	var block1Bottom = 0;
                	var block1Right = 0;
		}
		if ((tmpId = elem.getAttribute('separateBlock2')) != -1) {
			var sepBlock2 = document.getElementsByAttribute('myBlockId', tmpId, document.body)[0];
			var position2 = this.getAbsolutePosition(sepBlock2);
	                var block2Top = position2["top"];
        	        var block2Left = position2["left"];
			var block2Width = position2["width"];
                        var block2Height = position2["height"];
                	var block2Bottom = block2Top + block2Height;
                	var block2Right = block2Left + block2Width;
		} else {
			var block2Top = 0;
        	        var block2Left = 0;
			var block2Width = 0;
			var block2Height = 0
                	var block2Bottom = 0;
                	var block2Right = 0;
		}
		var separateType = elem.getAttribute('separateType');

		if (separateType == "1") {

			var offsetTop = block1Bottom;

			if (block1Left <= block2Left) {
				var offsetLeft = block1Left;
				if (block1Right <= block2Right) {
					var offsetWidth = block2Right - block1Left;
				} else {
					var offsetWidth = block1Width;
				}
			} else {
				var offsetLeft = block2Left;
				if (block2Right <= block1Right) {
					var offsetWidth = block1Right - block2Left;
				} else {
					var offsetWidth = block2Width
				}
			}
			var offsetHeight = block2Top - block1Bottom;

		} else if (separateType == "2") {

			if (block1Top <= block2Top) {
				var offsetTop = block1Top;
				if (block1Bottom <= block2Bottom) {
					var offsetHeight = block2Bottom - block1Top;
				} else {
					var offsetHeight = block1Height;
				}
			} else {
				var offsetTop = block2Top;
				if (block2Bottom <= block1Bottom) {
					var offsetHeight = block1Bottom - block2Top;
				} else {
					var offsetHeight = block2Height;
				}
			}
			var offsetLeft = block1Right;
			var offsetWidth = block2Left - block1Right;
		}

		if (offsetWidth <= 0 && offsetWidth > -3) {
			offsetLeft -= 1; offsetWidth = 3;
		}
		if (offsetHeight <= 0 && offsetWidth > -3) {
			offsetTop -= 1; offsetHeight = 3;
		}

                this.addLayer(offsetTop, offsetLeft, offsetWidth, offsetHeight, color, Id, "none");
	},

	getAbsolutePosition : function (elem) {
		var tmpElem = elem;
		var top = tmpElem.offsetTop;
		var left = tmpElem.offsetLeft;
		var width = tmpElem.offsetWidth;
		var height = tmpElem.offsetHeight;
		while (tmpElem.tagName != "BODY") {
                        if(tmpElem = tmpElem.offsetParent){
                                top += tmpElem.offsetTop;
                                left += tmpElem.offsetLeft;
                        } else {
                                break;
                        };
                };

		return {"top":top, "left":left, "width":width, "height":height};
	},

	getColor : function (index) {

		if (index == 0) return "#000080";
		if (index == 1) return "#006400";
		if (index == 2) return "#ffa500";
		if (index == 3) return "#ff0000";
		if (index == 4) return "#4b0082";
		if (index == 5) return "#696969";	
	
		var color = Math.floor(Math.random() * 0xFFFFFF).toString(16);	
		for(count = color.length; count < 6; count++){
			color = "0" + color;
		}
		return "#" + color; 
	},

	getMyBlockTypeColor : function (type) {

		if (type == "link") return "#CCCCCC";
		if (type == "maintext") return "YellowGreen";
		if (type == "unknown_block") return "Khaki";
		if (type == "img") return "Aquamarine";
		if (type == "header") return "orchid";
		if (type == "footer") return "FUCHSIA";
		if (type == "form") return "peru";
		if (type == "profile") return "pink";
		if (type == "address") return "lime";

		return "#000080";
	},
};



function showSeparator() {
	var Layer = new FloatLayer();

	var blocks = document.getElementsByAttribute('myblocktype', "", document.body);
	for ( iii=0; iii<blocks.length; iii++) {
        	var id = iii + 1;
		var color = Layer.getMyBlockTypeColor(blocks[iii].getAttribute("myblocktype"));	
              	Layer.addOverNode(blocks[iii], color, "block" + id);
	}

};


document.body.setAttribute("onload", "showSeparator();");


