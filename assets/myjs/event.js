var ws;

function ready(){

	// Websocket connection to main.pl
	if ('MozWebSocket' in window) {
		WebSocket = MozWebSocket;
	}
	if ('WebSocket' in window) {
		ws = new WebSocket('ws://' + window.location.host + '/event');
		ws.onopen = function() {
			ws.send('{\"pid\" : \"event\",\"type\" : \"make\",\"values\" : []}');
			if (getParameterByName('auth')) {
				ws.send('{\"pid\" : \"chat\",\"type\" : \"post\",\"values\" : ["auth","' + getParameterByName('auth') +'"]}');
			}
		};
		ws.onmessage = function(evt) {
			console.log(evt.data);
		};
		ws.onclose = function() {
		};
	} else {
		// browser does not support websockets
	}
}

$(document).ready(function(){
	ready();

	simpleDatepicker("start");
	simpleDatepicker("end");

	login();

	$("#hidden-btn").click(function(){
		brokenPattern();
	});


	$(".action-btn").click(function(){
		var message = $(this).attr('id');
		var email = $("#inputEmail").val();
		var password = $("#inputPassword").val();
		ws.send('{\"pid\" : \"chat\",\"type\" : \"post\",\"values\" : ["' + message + '","' + email +'","' + password +'"]}');
	});

	$(".enter").keyup(function(event){
	    if(event.keyCode == 13){
	        $("#login").click();
	    }
	});
	
	$("#login").click(function(){
		var email = $("#inputEmail").val();
		var password = $("#inputPassword").val();
		ws.send('{\"pid\" : \"chat\",\"type\" : \"post\",\"values\" : ["login","' + email +'","' + password +'"]}');
		ws.onmessage = function(evt) {
			console.log(evt.data);
			if (evt.data) {
				var str = evt.data;
				eval(str);
			}
		};
	});

});

var message = {
	auth:"Hej där! Ett mail har skickats till dig! :)", 
	bad:"Ooops! Det verkar som att fel lösenord, eller en ogiltig e-mail angivits.",
	stop:"Spisen har nu stängts av, och den här händelsen ignoreras vid framtida beräkningar.",
	ignore:"Den här händelsen ignoreras vid framtida beräkningar.",
	correct:"Ooops! Ursäkta att jag störde!",
	eventadded:"Jag kommer nu att ta hänsyn till den nya händelsen i mina uträkningar."
};

function printMessage(data){
	$("#printmessage #message").html(message[data]);
    $("#printmessage").fadeIn(500);
    $("#printmessage").animate({marginTop: "20vh"},1000);
	$("body").click(function(){
	    $("#printmessage").fadeOut(500);
    	$("#printmessage").animate({marginTop: "0vh"},1000);
	});
}

function zeroPad(num) {
  var zero = 2 - num.toString().length + 1;
  return Array(+(zero > 0 && zero)).join("0") + num;
}

function login(){
    $("#signin").fadeIn(500);
    $(".form-horizontal").animate({marginTop: "10vh"},1000);

	$(".close").click(function(){
	    $("#signin").fadeOut(500);
    	$(".form-horizontal").animate({marginTop: "0vh"},1000);
	});
}

function loginSuccess(){
    $("#signin").fadeOut(500);
	$(".form-horizontal").animate({marginTop: "0vh"},1000);
}

function loginFail(msg){
	$("#signin-message").remove();
	$("#signin-message-placeholder").append($("<div></div>").attr("id","#signin-message").text(message[msg]));
	login();
}

function brokenPattern(){
    $(".correct").fadeIn(1000);
    $(".correct .title").animate({marginTop: "0"},1000);
    $('.correct .info .btn').attr("disabled", false);
	$(".correct button").click(function(){
	    correctPattern();
	});    
}

function correctPattern(){
    $(".correct").fadeOut(1000);
    $(".correct .title").animate({marginTop: "-150px"},1000);
    $('.correct .info .btn').attr("disabled", true);
}

function statusBox(msg){
    $('#status-box').prepend("<p>"+msg+"</p>");
}

function addEvent(){
    $("#create").fadeIn(500);
    $(".form-horizontal").animate({marginTop: "10vh"},1000);

	$("#create .close").click(function(){
	    $("#create").fadeOut(500);
    	$(".form-horizontal").animate({marginTop: "0vh"},1000);
	});

	$("#create .addevent").click(function(){
		var startTime = $("#datepickerstart #year").val()+"-"+$("#datepickerstart #month").val()+"-"+$("#datepickerstart #day").val()+" "+$("#datepickerstart #hour").val()+":"+$("#datepickerstart #minute").val();
		var endTime = $("#datepickerend #year").val()+"-"+$("#datepickerend #month").val()+"-"+$("#datepickerend #day").val()+" "+$("#datepickerend #hour").val()+":"+$("#datepickerend #minute").val();
		var email = $("#inputEmail").val();
		var password = $("#inputPassword").val();
		ws.send('{\"pid\" : \"chat\",\"type\" : \"post\",\"values\" : ["addevent","' + dateToTimestamp(startTime) + '","' + dateToTimestamp(endTime) + '","' + email +'","' + password +'"]}');
	    $("#create").fadeOut(500);
    	$(".form-horizontal").animate({marginTop: "0vh"},1000);
	});
}

function dateToTimestamp(date){
	var date = new Date(date);
	return (date.getTime() / 1000);
}

function showEvents(){
    $("#list").fadeIn(500);
	$("#list .closemessage").click(function(){
	    $("#list").fadeOut(500);
	});
}

function cleanEvents(){
	$("#list table").remove();
	$('#list').append('<table class="table"><tr><th>Starttid</th><th>Sluttid</th><th>Meddelande</th><th></th></tr></table>');
}

function printEvents(status, starttime, message, endtime){
	var style;
	if (status > 0) {
		status = "pågående";
		endtime = "";
		style="current";
	} else{
		status = "";
		endtime = formatTime(endtime);
	}
	if (message = "unknown")
		message = "";

	$('#list table tr:last').after('<tr class="'+style+'"><td>'+formatTime(starttime)+'</td><td>'+endtime+'</td><td>'+message+'</td><td>'+status+'</td></tr>');
}

var formatTime = function(unixTimestamp) {
	var monthName = Array("januari","februari","mars","april","maj","juni","juli","augusti","september","oktober","november","december");

    var dt = new Date(unixTimestamp * 1000);

    var year = dt.getYear();
    var month = monthName[dt.getMonth()];
    var day = dt.getDate();

    var hours = zeroPad(dt.getHours());
    var minutes = zeroPad(dt.getMinutes());
    var seconds = zeroPad(dt.getSeconds());

    return day + " " + month + " " + hours + ":" + minutes;
}        

function getParameterByName(name) {
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
    var regex = new RegExp("[\\?&]" + name + "=([^&#]*)"),
        results = regex.exec(location.search);
    return results === null ? "" : decodeURIComponent(results[1].replace(/\+/g, " "));
}